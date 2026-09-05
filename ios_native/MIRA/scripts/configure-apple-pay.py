"""Only enable PaymentSheet Apple Pay for an explicitly provisioned merchant."""
import os
import pathlib
import plistlib
import re

root = pathlib.Path(__file__).resolve().parents[1]
merchant = os.environ.get("CAPTRO_APPLE_PAY_MERCHANT_ID", "").strip()
if merchant and not re.fullmatch(r"merchant\.[A-Za-z0-9.-]+", merchant):
    raise SystemExit("CAPTRO_APPLE_PAY_MERCHANT_ID must be a registered Apple merchant identifier")

for path, key, value in (
    (root / "AppTarget/Info.plist", "CaptroApplePayMerchantIdentifier", merchant),
    (root / "AppTarget/Captro.entitlements", "com.apple.developer.in-app-payments", [merchant]),
):
    with path.open("rb") as stream:
        data = plistlib.load(stream)
    if merchant:
        data[key] = value
    else:
        data.pop(key, None)
    with path.open("wb") as stream:
        plistlib.dump(data, stream, sort_keys=False)

print("Apple Pay merchant configured; signing profile must authorize it." if merchant
      else "No Apple Pay merchant configured. PaymentSheet will not advertise Apple Pay.")
