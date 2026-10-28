"""Generate Android Firebase resources from a local (untracked) config."""
import json
import pathlib
import sys
from xml.sax.saxutils import escape

config = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
client = next((c for c in config["client"] if c["client_info"]["android_client_info"]["package_name"] == "com.adoetzchat.messenger"), None)
if client is None:
    raise SystemExit("Firebase config must contain com.adoetzchat.messenger")
project = config["project_info"]
values = {
    "google_app_id": client["client_info"]["mobilesdk_app_id"],
    "gcm_defaultSenderId": project["project_number"],
    "google_api_key": client["api_key"][0]["current_key"],
    "project_id": project["project_id"],
}
if "storage_bucket" in project:
    values["google_storage_bucket"] = project["storage_bucket"]
dest = pathlib.Path("android/app/src/main/res/values/firebase_config.xml")
dest.write_text('<resources>\n' + ''.join(f'  <string name="{k}" translatable="false">{escape(v)}</string>\n' for k, v in values.items()) + '</resources>\n', encoding='utf-8')
print("Firebase Android resources configured.")
