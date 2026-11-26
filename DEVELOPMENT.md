# Development

These instructions are for building and testing the Connect IQ app from source. The [README](README.md) covers use and installation on the watch.

## Prerequisites

- Install the [Garmin Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/) and the device bundle labelled **fēnix 8 47mm / 51mm / tactix 8 47mm / 51mm / quatix 8 47mm / 51mm**. The project uses the shared `fenix847mm` target.
- Keep a Garmin developer signing key outside this repository. Set `DEVELOPER_KEY` to the absolute path of its `.der` file. Do not publish either the `.der` or `.pem` private key. Keep the same key for updates to an installed app.
- Set `CONNECT_IQ_SDK_HOME` to your installed SDK directory. Install `jq` to run the response contract check.

To make a new signing key if you do not already have one:

```bash
mkdir -p "$HOME/.config/garmin-connectiq/meteo-swiss-quatix8"
chmod 700 "$HOME/.config/garmin-connectiq/meteo-swiss-quatix8"
openssl genrsa -out "$HOME/.config/garmin-connectiq/meteo-swiss-quatix8/developer_key.pem" 4096
openssl pkcs8 -topk8 -inform PEM -outform DER \
  -in "$HOME/.config/garmin-connectiq/meteo-swiss-quatix8/developer_key.pem" \
  -out "$HOME/.config/garmin-connectiq/meteo-swiss-quatix8/developer_key.der" -nocrypt
chmod 600 "$HOME/.config/garmin-connectiq/meteo-swiss-quatix8"/developer_key.*
```

## Build

From the project directory:

```bash
export CONNECT_IQ_SDK_HOME="/path/to/connectiq-sdk"
export DEVELOPER_KEY="$HOME/.config/garmin-connectiq/meteo-swiss-quatix8/developer_key.der"
./build.sh
./build-device.sh
```

The simulator build is `bin/MeteoSwissWeather.prg`. The signed release build for direct watch installation is `bin/MeteoSwissWeather-device.prg`. Build outputs stay out of Git.

## Simulator

```bash
open "$CONNECT_IQ_SDK_HOME/bin/ConnectIQ.app"
"$CONNECT_IQ_SDK_HOME/bin/monkeydo" bin/MeteoSwissWeather.prg fenix847mm
```

Set a simulated location and allow Communications and Positioning. To preview the glance, turn on **Settings → Glance Launch Mode** in the simulator before loading the app.

## Tests

Check the bundled response fixture:

```bash
bash tests/check-contract.sh
```

Run the Monkey C tests in the simulator:

```bash
"$CONNECT_IQ_SDK_HOME/bin/monkeyc" -f monkey.jungle -d fenix847mm \
  -o bin/MeteoSwissWeather-test.prg -y "$DEVELOPER_KEY" -t
"$CONNECT_IQ_SDK_HOME/bin/monkeydo" bin/MeteoSwissWeather-test.prg fenix847mm -t
```

To check a current Open-Meteo response, fetch the same fields used by the app and pass the saved JSON to `tests/check-contract.sh`.

## Project notes

- `source/MeteoSwissService.mc` handles location, forecast requests, and response mapping. `source/MeteoSwissCache.mc` stores daily and hourly forecasts separately. The views render the watch app, hourly detail, and glance.
- The app currently requests MeteoSwiss ICON-CH2 through Open-Meteo. MeteoSwiss's bulk forecast files are too large for a direct watch request. A future MeteoSwiss point-query API will need its own response mapping and careful checks of units, time periods, and symbol codes.
- The weather symbols in `resources/icons` are original. MeteoSwiss's own graphics are not included.
- Keep the forecast attribution in public descriptions: **MeteoSwiss ICON-CH2 via Open-Meteo**. Review the providers' terms before distributing the app, particularly if the app becomes commercial or attracts many users.

## Publish on GitHub

This project already has a local Git commit. The `.gitignore` excludes signing keys, build outputs, and local files. Check the tracked files before publishing:

```bash
git status --short
git ls-files
```

Create an **empty** repository on GitHub, without adding another README, license, or `.gitignore`. Then connect and push this project, replacing `YOUR_USERNAME` with your GitHub username:

```bash
git remote add origin "https://github.com/YOUR_USERNAME/meteo-swiss-quatix8.git"
git push -u origin main
```

Do not upload the whole local folder through a file browser: it may include ignored local files such as `bin/`.
