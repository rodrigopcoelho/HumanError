#!/bin/bash
# Turns the source photographs in assets/photography into the game's corrupted
# portraits and environments. Requires ImageMagick 7 ("magick").
# Usage: bash tools/process_photos.sh      (run from the project root)
set -e
SRC=assets/photography
P=assets/portraits
E=assets/environments
TMP=$(mktemp -d)
mkdir -p "$P" "$E"

# Shared finishing pass: green duotone, RGB channel separation, grain, JPEG crush.
finish() { # in out split
  magick "$1" -colorspace Gray -sigmoidal-contrast 4x45% +level-colors '#070b09','#cfe6c8' "$TMP/base.png"
  magick "$TMP/base.png" \( +clone -roll +$3+0 \) \( -clone 0 -roll -$3+1 \) \
    \( -clone 1 -channel R -separate \) \( -clone 0 -channel G -separate \) \( -clone 2 -channel B -separate \) \
    -delete 0-2 -combine -attenuate 0.35 +noise Gaussian -quality 14 "$TMP/crush.jpg"
  magick "$TMP/crush.jpg" -quality 88 "$2"
}

# portrait: name source crop(WxH+X+Y) eye_band_y
portrait() {
  magick "$SRC/$2" -crop "$3" +repage -resize '400x500!' -colorspace Gray "$TMP/p.png"
  # Obscure the eyes: pixelate the band and shove it sideways (pixel displacement),
  # so nobody in these archive photographs is identifiable.
  magick "$TMP/p.png" \
    \( -clone 0 -crop 400x64+0+$4 +repage -scale 6% -scale 400x64! -roll +26+0 \) -geometry +0+$4 -composite \
    \( -clone 0 -crop 400x12+0+$(($4+110)) +repage -roll -40+0 \) -geometry +0+$(($4+110)) -composite \
    \( -clone 0 -crop 400x8+0+$(($4-70)) +repage -roll +60+0 \) -geometry +0+$(($4-70)) -composite \
    \( -clone 0 -crop 120x90+250+380 +repage -negate \) -geometry +250+380 -composite \
    "$TMP/p2.png"
  finish "$TMP/p2.png" "$P/$1.jpg" 5
}

portrait maria src_portrait_f1.jpg 420x525+465+110 205
portrait elena src_portrait_f2.jpg 400x500+522+230 205
portrait sarah src_portrait_f4.jpg 520x650+505+180 215
portrait david src_portrait_m1.jpg 440x550+422+430 168
portrait james src_portrait_m2.jpg 440x550+397+405 246
# UNKNOWN INSTANCE 07 (and the analyst's own record): the mean of everyone you verified.
magick "$P/maria.jpg" "$P/david.jpg" "$P/elena.jpg" "$P/james.jpg" "$P/sarah.jpg" -evaluate-sequence mean \
  -sigmoidal-contrast 5x40% \( +clone -crop 400x30+0+300 +repage -roll +90+0 \) -geometry +0+300 -composite -quality 88 "$P/composite.jpg"

# environment: name source extra-ops...
environment() {
  local name=$1 src=$2; shift 2
  magick "$SRC/$src" -resize '1280x720^' -gravity center -extent 1280x720 "$@" "$TMP/e.png"
  finish "$TMP/e.png" "$E/$name.jpg" 4
}

environment corridor_a src_corridor.jpg -fill '#c9c9c9' -draw 'rectangle 96,70 330,300'
environment corridor_b src_corridor.jpg -fill '#c9c9c9' -draw 'rectangle 96,70 330,300' -flop -modulate 85
# A figure-shaped absence at the vanishing point.
environment corridor_c src_corridor.jpg -fill '#c9c9c9' -draw 'rectangle 96,70 330,300' -modulate 60 -fill black -draw 'roundrectangle 622,300 652,400 12,12' -draw 'circle 637,288 637,301' -blur 0x2.5
environment corridor_d src_corridor_dark.jpg -modulate 110 -fill black -draw 'roundrectangle 610,330 660,520 18,18' -draw 'circle 635,308 635,330' -blur 0x3
environment waiting_room src_waiting_room.jpg
environment window_a src_car_park.jpg -modulate 115
environment window_b src_car_park.jpg -resize '150%x100%!' -gravity center -extent 1280x720 -modulate 55 \
  \( +clone -crop 1280x40+0+330 +repage -roll +200+0 \) -gravity NorthWest -geometry +0+330 -composite
environment server_room src_computer_room.jpg -modulate 80
environment desktop_wallpaper src_building.jpg -modulate 70 -blur 0x1.5

# Application icon
magick -size 128x128 xc:'#090d0b' -fill none -stroke '#9abf9a' -strokewidth 4 -draw 'rectangle 10,10 118,118' \
  -fill '#9e2929' -stroke none -draw 'rectangle 28,58 100,70' -fill '#9abf9a' -draw 'rectangle 28,34 48,46' -draw 'rectangle 80,34 100,46' \
  -draw 'rectangle 28,84 100,92' ui/icons/icon.png
rm -rf "$TMP"
echo "photos processed"
