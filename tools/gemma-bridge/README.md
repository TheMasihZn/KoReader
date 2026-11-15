# Gemma bridge

One Gemma conversation that you can continue from the laptop or the phone.

```
phone (KOReader OS "Gemma" app) ──Wi-Fi──► gemma_bridge.py (laptop) ──► Ollama (gemma)
laptop browser http://localhost:8765 ───────┘
```

## On the laptop (Ubuntu)

```
ollama pull gemma3            # once, if you don't have a Gemma model yet
sudo apt install espeak-ng    # optional: for read-aloud (or piper, see below)
python3 gemma_bridge.py
```

The terminal shows the address and PIN for the phone. Open http://localhost:8765 on the laptop to chat from there. It's the same conversation the phone sees.

If the phone can't reach the laptop, allow the port through the firewall: `sudo ufw allow 8765/tcp` and `sudo ufw allow 47801/udp` (the second port is for "Find on Wi-Fi").

For a more natural voice, install [piper](https://github.com/rhasspy/piper) and start the bridge with
`PIPER_MODEL=/path/to/voice.onnx python3 gemma_bridge.py`.

## On the phone

Home → **Gemma** → ⋯ → **Connect to laptop** → **Find on Wi-Fi** (or type the address), then enter the PIN.

- **Write** opens the keyboard. The row above it has **Paste**, **▶** (read the last reply aloud) and **⟲** (repeat the last clip; hold it for recent clips).
- Sound plays through Android, so it goes to your Bluetooth earbuds when they're connected.
- Messages written while the laptop is away wait in an outbox and go out on their own later. They're never sent twice.
- The conversation is saved on the phone, so you can read it offline.

## What's kept where

- Laptop: `~/.gemma-bridge/sessions/` (conversations), `~/.gemma-bridge/audio/` (spoken replies, made once and reused), `~/.gemma-bridge/config.json` (the PIN).
- Phone: `koreader/settings/kos_gemma.lua` (copy of the conversation, plus the outbox) and `kos_audio.lua` (recently played clips).

## For other apps (messengers…)

- `apps/kos/audiopipeline` handles play, repeat and history for any app: `Audio.play{ url = …, title = … }`.
- `apps/kos/keyboardtoolbar` builds the Paste + audio row that sits on top of the keyboard. The future KOReader OS keyboard will show the same row.
