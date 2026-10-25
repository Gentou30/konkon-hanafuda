#!/usr/bin/env bash
# 親分たちと店の背景
cd ~/Projects/konkon-hanafuda
S="Cute chunky kemono (furry) anime game art, thick clean dark outlines, soft cel shading, warm saturated colors, all-ages, not sexualized."
B="Bust-up portrait from the chest up, character centered, plain flat pure green (#00FF00) background with nothing else, no text."
gen(){ tools/gen_image.sh "$@" & }
gen art/raw/boss_ponkichi.png "$S $B 'Ponkichi', a big round tanuki (raccoon dog) yakuza-style gambling boss, wearing a straw hat and a dark blue kimono, holding a large sake gourd, a leaf on his head, sly confident grin, comedic not scary."
gen art/raw/boss_otama.png "$S $B 'Otama', an elegant two-tailed cat yokai (nekomata) gambler lady, black and white cat with a clear cat muzzle, purple kimono with butterfly patterns, holding a folding fan and a hanafuda card, both tails visible, mischievous smile, sharp claws. Wholesome, not sexualized."
gen art/raw/boss_kurobo.png "$S $B 'Kurobo', a karasu-tengu crow yokai with a black-feathered bird face and beak, small black tokin cap, yamabushi mountain-monk outfit with pom-poms, big black wings, holding a feather fan, haughty proud pose."
gen art/raw/boss_kawataro.png "$S $B 'Kawataro', a muscular friendly kappa (green turtle-like river yokai with a beak, a water dish on head and a shell), wearing a sumo mawashi and a happi coat, holding a cucumber like a cigar, flexing confidently, comedic big-brother vibe."
gen art/raw/boss_tamamo.png "$S $B 'Tamamo', the boss of the gambling den, a majestic golden nine-tailed fox (kyubi) with a clear fox muzzle, nine fluffy golden tails fanned behind, elegant layered red and gold kimono, hairpins, holding a long pipe-free folding fan, faint purple fox-fire flames around, calm dangerous smile, regal. Wholesome, not sexualized."
gen art/raw/bg_shop.png "Background illustration for a game, no characters, no text: a small yokai night-market stall (yatai) at a torii-lined shrine path at night, lantern light, shelves with lucky charms (omamori), maneki-neko figures, paper talismans (ofuda), scrolls and small spirit figurines for sale, blue will-o'-wisps, purple mist. Painterly anime background, warm reds and indigo, slightly dark so UI stays readable. 16:9 wide."
wait
