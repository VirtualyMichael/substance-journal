# Substance Journal for Wear OS (Pixel Watch)

The watch app shows your live curve (a line per active substance, in its colour, with the names), the
blood alcohol estimate, your recent doses and a **Same as last time** button. It works with the phone
app: the phone sends the numbers over Bluetooth, and the watch asks the phone to log a dose.

## Turn it on (phone)

1. Install the watch app (below).
2. Phone app: **Settings, Reminders and notifications, Watch**.
3. Switch on **Show on my watch**. Switch on **Let the watch log "Same as last time"** if you want the
   button to work. It logs from the watch even with the phone locked and the app closed, and it skips the
   app lock, because the watch has its own lock.

## Install the watch app (once per update)

The watch app has the same package name and signing key as the phone app, which is what lets them talk.

1. On the watch: **Settings, System, About, Versions**, tap **Build number** seven times to unlock
   developer options. Then **Settings, Developer options**, turn on **ADB debugging** and **Debug over
   Wi-Fi** (the watch and this PC must be on the same Wi-Fi).
2. Note the watch's address shown there (like `192.168.1.50:5555`). If it asks to pair, use
   **Pair new device** and note the pairing address and code.
3. On this PC, in PowerShell from the repository folder:

   ```powershell
   scripts\install_watch.ps1 -Address 192.168.1.50:5555
   # first time only, if the watch wants a pairing code:
   scripts\install_watch.ps1 -Address 192.168.1.50:5555 -PairAddress 192.168.1.50:41234 -PairCode 123456
   ```

   The script builds the watch app, connects to the watch and installs it. Open **Substance Journal** on
   the watch; it asks the phone for fresh numbers.

## Notes

- Substance names and doses are shown on the watch whenever it is awake; they are not hidden when it is
  locked.
- The numbers are the same estimates as in the phone app, not medical advice.
- If the watch says "Waiting for the phone", check the **Watch** switch in the phone app and that the
  watch is connected in the Pixel Watch app.
