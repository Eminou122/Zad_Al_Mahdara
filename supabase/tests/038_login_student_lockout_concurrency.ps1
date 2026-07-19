param(
  [string]$Container = 'supabase_db_Zad_Al_Mahdara'
)

$ErrorActionPreference = 'Stop'
if ($Container -notlike 'supabase_db_*') {
  throw 'Concurrency tests are restricted to a local Supabase DB container.'
}

$phone = '00000338'
$correctPin = '8642'
$wrongPin = '9753'

function Invoke-Sql([string]$Sql) {
  $result = & docker exec $Container psql -U postgres -d postgres -qAt -c $Sql
  if ($LASTEXITCODE -ne 0) { throw "psql failed with exit code $LASTEXITCODE" }
  return ($result | Out-String).Trim()
}

function Invoke-ParallelSql([string[]]$Queries) {
  $jobs = foreach ($query in $Queries) {
    Start-Job -ScriptBlock {
      param($containerName, $sql)
      $result = & docker exec $containerName psql -U postgres -d postgres -qAt -c $sql
      if ($LASTEXITCODE -ne 0) { throw "psql failed with exit code $LASTEXITCODE" }
      ($result | Out-String).Trim()
    } -ArgumentList $Container, $query
  }
  try {
    return @($jobs | Wait-Job | Receive-Job)
  } finally {
    $jobs | Remove-Job -Force
  }
}

try {
  Invoke-Sql @"
delete from public.profiles where phone_number = '$phone';
insert into public.profiles (
  display_name, phone_number, phone_masked, pin_hash, is_admin, is_active
) values (
  'AUTH-F2 concurrency disposable',
  '$phone',
  '00****38',
  crypt('$correctPin', gen_salt('bf', 8)),
  false,
  true
);
"@ | Out-Null

  $wrongQuery = "select pg_sleep(0.2); select public.login_student('$phone','$wrongPin')->>'error';"
  $wrongResults = Invoke-ParallelSql (@($wrongQuery) * 5)
  if (@($wrongResults | Where-Object { $_ -notmatch 'INVALID_CREDENTIALS' }).Count -ne 0) {
    throw 'Concurrent wrong attempts did not all return the generic failure.'
  }
  $wrongState = Invoke-Sql @"
select failed_login_count || '|' || (locked_until > now()) || '|' ||
  (select count(*) from public.app_sessions where profile_id = p.id)
from public.profiles p where phone_number = '$phone';
"@
  if ($wrongState -ne '5|true|0' -and $wrongState -ne '5|t|0') {
    throw "Concurrent wrong-attempt state was $wrongState"
  }
  'A concurrent wrong attempts: PASS'

  Invoke-Sql @"
delete from public.app_sessions
where profile_id = (select id from public.profiles where phone_number = '$phone');
update public.profiles
set failed_login_count = 4, locked_until = null, last_login_at = null
where phone_number = '$phone';
"@ | Out-Null
  $raceResults = Invoke-ParallelSql @(
    "select pg_sleep(0.2); select public.login_student('$phone','$wrongPin')->>'error';",
    "select pg_sleep(0.2); select public.login_student('$phone','$correctPin') ? 'session_token';"
  )
  $raceState = Invoke-Sql @"
select failed_login_count || '|' || (locked_until > now()) || '|' ||
  (select count(*) from public.app_sessions where profile_id = p.id)
from public.profiles p where phone_number = '$phone';
"@
  if ($raceState -notin @('5|true|0', '5|t|0', '1|false|1', '1|f|1')) {
    throw "Correct/wrong race produced an unserialized state: $raceState"
  }
  'B correct/wrong ordering: PASS'

  Invoke-Sql @"
delete from public.app_sessions
where profile_id = (select id from public.profiles where phone_number = '$phone');
update public.profiles
set failed_login_count = 0, locked_until = null, last_login_at = null
where phone_number = '$phone';
"@ | Out-Null
  $correctQuery = "select pg_sleep(0.2); select public.login_student('$phone','$correctPin') ? 'session_token';"
  $correctResults = Invoke-ParallelSql @($correctQuery, $correctQuery)
  if (@($correctResults | Where-Object { $_ -notmatch '(?m)^t(rue)?$' }).Count -ne 0) {
    throw 'Both concurrent correct logins must succeed.'
  }
  $correctState = Invoke-Sql @"
select failed_login_count || '|' || (locked_until is null) || '|' ||
  (select count(*) from public.app_sessions where profile_id = p.id) || '|' ||
  (select count(distinct token_hash) from public.app_sessions where profile_id = p.id)
from public.profiles p where phone_number = '$phone';
"@
  if ($correctState -notin @('0|true|2|2', '0|t|2|2')) {
    throw "Concurrent correct-login state was $correctState"
  }
  'C concurrent correct logins: PASS'
} finally {
  Invoke-Sql "delete from public.profiles where phone_number = '$phone';" | Out-Null
}
