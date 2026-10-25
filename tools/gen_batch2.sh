#!/usr/bin/env bash
# キャラ差分・親分・タイトル（参照画像で同じキャラを保つ）
cd ~/Projects/konkon-hanafuda
S="Cute chunky kemono (furry) anime game art, thick clean dark outlines, soft cel shading, warm saturated colors, all-ages, not sexualized."
B="Bust-up portrait from the chest up, character centered, plain flat pure green (#00FF00) background with nothing else, no text."
K="the same fox character 'Kon' as the reference image (orange round fox kid, white muzzle, green leaf on head, red-and-white happi, golden bell)"
gen(){ tools/gen_image.sh "$@" & }
gen art/raw/kon_normal.png "$S $B $K, cheerful relaxed smile, one paw waving." art/raw/kon_base.png
gen art/raw/kon_happy.png "$S $B $K, overjoyed, eyes closed in a big happy grin, both paws up, sparkles, holding gold coins." art/raw/kon_base.png
gen art/raw/kon_panic.png "$S $B $K, panicking, wide teary eyes, mouth open in a scream, sweat drops, fur puffed up, paws on cheeks." art/raw/kon_base.png
gen art/raw/kon_smug.png "$S $B $K, sly scheming smug grin, half-lidded eyes, one paw hiding a hanafuda card behind its back, little sparkle." art/raw/kon_base.png
gen art/raw/gin_bust.png "$S $B the same silver-white guardian fox 'Gin' as the reference image (red bib, pale blue swirl markings), shouting a comedic retort with a sharp pointing paw (tsukkomi pose), annoyed angry eyebrows, vein mark." art/raw/gin_base.png
gen art/raw/title.png "$S Key visual illustration for a game title screen, no text, no letters, 16:9 wide. In front of a glowing yokai gambling den at night with red paper lanterns, a torii gate and blue will-o'-wisp flames, the orange round fox kid 'Kon' (first reference) is cheerfully throwing a fan of hanafuda cards into the air, while the silver guardian fox 'Gin' (second reference) stands behind with a facepalm. Hanafuda cards and gold coins flutter around. Leave the upper-left third relatively calm and dark for a title logo." art/raw/kon_base.png art/raw/gin_base.png
wait
