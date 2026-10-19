#!/usr/bin/env python3
"""fetch-logo.py <out.png> <grid-color>: Arch logo as an LED dot matrix for
the terminal fetch (fastfetch logo). White logo dots on a grid of small faint
dots in <grid-color> (the wallpaper's dim tone). Run by set-wallpaper.sh."""
import subprocess
import sys

out, grid_color = sys.argv[1:3]
N, SIZE = 30, 600              # 30x30 dots on a 600px image
LOGO = "#ececec"
GLYPH = ""               # nf-linux-archlinux
cell = SIZE / N

font = subprocess.run(["fc-match", "-f", "%{file}", "JetBrainsMono Nerd Font Propo"],
                      capture_output=True, text=True, check=True).stdout

# Draw the glyph big, shrink it to the dot grid, read each cell's brightness
txt = subprocess.run(["magick", "-size", f"{SIZE}x{SIZE}", "xc:black", "-font", font,
                      "-pointsize", "470", "-fill", "white", "-gravity", "center",
                      "-annotate", "+0+20", GLYPH, "-resize", f"{N}x{N}!", "-depth", "8", "txt:-"],
                     capture_output=True, text=True, check=True).stdout

dots = []
for line in txt.splitlines()[1:]:              # "x,y: (..)  #RRGGBB  ..."
    pos, rest = line.split(":", 1)
    x, y = map(int, pos.split(","))
    cx, cy = (x + .5) * cell, (y + .5) * cell
    if int(rest.split("#")[1][:2], 16) > 110:  # inside the logo
        dots.append(f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{cell * .40:.1f}" fill="{LOGO}"/>')
    else:
        dots.append(f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{cell * .16:.1f}" '
                    f'fill="{grid_color}" fill-opacity=".45"/>')

svg = f'<svg xmlns="http://www.w3.org/2000/svg" width="{SIZE}" height="{SIZE}">{"".join(dots)}</svg>'
subprocess.run(["magick", "-background", "none", "svg:-", out], input=svg.encode(), check=True)
