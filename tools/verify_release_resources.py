"""Check dynamically named Android resources in the actual built APK.

Unit/widget tests cannot detect R8 removing a drawable referenced only by Dart.
Resource names must remain in the compiled resource table for getIdentifier().
"""
from pathlib import Path
import sys
import zipfile

apk = Path(sys.argv[1])
with zipfile.ZipFile(apk) as archive:
    table = archive.read('resources.arsc')
    required = ['ic_notification', 'ic_adoetz']
    if Path('android/app/google-services.json').exists():
        required += ['google_app_id', 'google_api_key', 'gcm_defaultSenderId', 'project_id']
    missing = [name for name in required if name.encode() not in table and name.encode('utf-16-le') not in table]
    if missing:
        raise SystemExit('Required Android resources removed from APK: ' + ', '.join(missing))
print('Verified notification and configured Firebase resources in built APK')
