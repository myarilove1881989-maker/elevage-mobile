"""Run native assertions twice in separate Android instrumentation processes."""
import subprocess
for attempt in range(2):
    result=subprocess.run(['adb','shell','am','instrument','-w',
      'com.elevage.app.offlinevalidation.test/androidx.test.runner.AndroidJUnitRunner'],
      capture_output=True,text=True,timeout=180)
    print(result.stdout,flush=True)
    assert (result.returncode==0 and 'OK (1 test)' in result.stdout and 'FAILURES!!!' not in result.stdout), 'Native Android assertions did not pass'
