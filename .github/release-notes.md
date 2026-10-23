
## Download

Pick your system under **Assets** below:

| System | File | Then |
|---|---|---|
| **Mac** (Apple Silicon or Intel) | `SendIt-macOS.zip` | Unzip, drag **SendIt** to Applications, open it. macOS will say it can't verify the app: click **Done**, open **System Settings → Privacy & Security**, click **Open Anyway** next to SendIt, then confirm. You only do this once. |
| **Windows** (64-bit) | `SendIt-Windows-x86_64.zip` | Unzip, double-click `SendIt.exe`. If SmartScreen says "Windows protected your PC", click **More info → Run anyway**. |
| **Linux** (x86_64) | `SendIt-Linux-x86_64.tar.gz` | `tar xzf SendIt-Linux-x86_64.tar.gz`, then run `./SendIt.x86_64` from the new folder. |

SendIt isn't code-signed or notarized yet, which is why Mac and Windows show a warning. The code is open source and `SHA256SUMS` lets you verify your download. Needs a GPU with Vulkan 1.2 drivers on Windows and Linux (any PC from the last several years); Macs use Metal.
