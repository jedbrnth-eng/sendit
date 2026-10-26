# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name PlateText
## Number-plate text: uppercase A-Z, 0-9 and single spaces, MAX_LEN characters, profanity-filtered
## (with leetspeak and spacing folded out before matching). Pure, unit-tested.

const MAX_LEN := 8
const FALLBACK := "SEND IT"
## Plates offered on a controller (no keyboard needed). All fictional.
const PRESETS := ["SEND IT", "GAP GOD", "NO HESI", "777", "LANE 5", "NIGHT 1", "GO FAST", "ZOOM"]
## Folded forms (after leet folding and dropping spaces). Substring match, so keep them specific.
const BLOCK := ["FUCK", "FUK", "FCK", "SHIT", "CUNT", "BITCH", "COCK", "DICK", "PUSSY", "SLUT", "WHORE",
	"FAG", "NIGGA", "NIGGER", "NIGER", "RAPE", "NAZI", "KKK", "HITLER", "PENIS", "VAGINA", "ASSHOLE",
	"TWAT", "WANK", "SEX", "PORN", "RETARD", "SPIC", "CHINK", "KIKE", "HOMO"]
const LEET := {"0": "O", "1": "I", "3": "E", "4": "A", "5": "S", "7": "T", "8": "B", "9": "G", "$": "S", "@": "A", "!": "I"}


static func sanitize(text: String) -> String:
	var out := ""
	var last_space := true
	for ch in text.to_upper():
		var c := ch.unicode_at(0)
		if (c >= 65 and c <= 90) or (c >= 48 and c <= 57):
			out += ch
			last_space = false
		elif ch == " " and not last_space:
			out += " "
			last_space = true
	out = out.strip_edges()
	if out.length() > MAX_LEN:
		out = out.substr(0, MAX_LEN).strip_edges()
	return out


static func is_clean(text: String) -> bool:
	var folded := ""
	for ch in text.to_upper():
		var f: String = LEET.get(ch, ch)
		var c := f.unicode_at(0)
		if c >= 65 and c <= 90:
			folded += f
	# Also squash doubled letters ("FUUCK") so stretching doesn't slip past.
	var squashed := ""
	for ch in folded:
		if squashed.is_empty() or squashed[squashed.length() - 1] != ch:
			squashed += ch
	for bad in BLOCK:
		if folded.contains(bad) or squashed.contains(bad):
			return false
	return true


## What gets stored: sanitised, clean, non-empty, else the fallback.
static func commit(text: String) -> String:
	var s := sanitize(text)
	if s == "" or not is_clean(s):
		return FALLBACK
	return s
