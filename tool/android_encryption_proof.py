"""Read only synthetic files from the isolated instrumentation application."""
import json,re,sqlite3,subprocess
from pathlib import Path
package='com.elevage.app.offlinevalidation'
output=Path('build/android-foundations-proof');output.mkdir(parents=True,exist_ok=True)
def read_file(path):
    return subprocess.check_output(['adb','exec-out','run-as',package,'cat',path])
vector=json.loads(read_file('files/native-proof-vector.json'))
assert vector['private_key_exportable'] is False
assert set(vector)=={'public_key','installation_uuid','challenge_id','signature','message','private_key_exportable'}
(output/'native-proof-vector.json').write_text(json.dumps(vector),encoding='utf-8')
names=subprocess.check_output(['adb','exec-out','run-as',package,'find','.', '-maxdepth','3','-type','f','-name','farm_*.db']).decode().splitlines()
databases=[name for name in names if re.fullmatch(r'farm_[a-f0-9]{64}_1\.db',Path(name).name)]
assert databases,f'Synthetic encrypted cache missing; database paths: {names!r}'
for index,name in enumerate(databases):
    assert name.startswith('./') and '..' not in Path(name).parts
    data=read_file(name)
    assert not data.startswith(b'SQLite format 3\x00')
    file=output/f'synthetic-encrypted-cache-{index}.db';file.write_bytes(data)
    database=sqlite3.connect(file.resolve().as_uri()+'?mode=ro',uri=True)
    try:
        database.execute('SELECT name FROM sqlite_master').fetchall()
    except sqlite3.DatabaseError:
        pass
    else:
        raise AssertionError('Android cache readable by ordinary SQLite')
    finally:
        database.close()
print(f'Android native cipher proof PASS: {len(databases)} synthetic cache(s) unreadable by ordinary SQLite')
