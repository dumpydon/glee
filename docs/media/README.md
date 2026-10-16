# Glee launch video

[glee-launch.mp4](glee-launch.mp4) is the 19-second Glee launch clip, exported at 1920×1080 and 60 fps with H.264 video and AAC sound. The menu bar uses Glee’s native white symbol, and the end card links to this repository.

The interface illustrates Liquid Glass on supported macOS versions. macOS 14/15 use the native fallback controls. Closed-lid mode requires setup and a confirmed active session.

The production edit can be regenerated on macOS with `script/create_launch_video.py` and the 19-second production master. Use an isolated Python environment with `opencv-python-headless==4.12.0.88`, `numpy==2.2.6`, and `Pillow==11.3.0`, plus FFmpeg. The script refuses an existing output or overwriting the master.

Copyright © 2026 dumpydon.
