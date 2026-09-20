import type { StampData } from "./types";
/** Demo records only. No active offers, dates or memberships. */
export const EXAMPLES: StampData[] = [
  {
    "type": "moment",
    "variant": "moment-paper",
    "title": "A little of today",
    "meta": "WEST VILLAGE · NYC",
    "footer": "SEP 20, 2026",
    "compactText": "WEST VILLAGE · NYC"
  },
  {
    "type": "moment",
    "variant": "moment-postal",
    "title": "Slow Sunday",
    "meta": "CENTRAL PARK",
    "footer": "SEP 20 · NEW YORK",
    "compactText": "CENTRAL PARK · NYC"
  },
  {
    "type": "moment",
    "variant": "moment-voice",
    "title": "On my way home",
    "meta": "A NOTE FROM TODAY",
    "footer": "",
    "sideMain": "0:42",
    "waveform": [
      0.12,
      0.28,
      0.21,
      0.49,
      0.35,
      0.78,
      0.64,
      0.93,
      0.48,
      0.65,
      0.39,
      0.87,
      0.51,
      0.99,
      0.56,
      0.42,
      0.77,
      0.59,
      0.26,
      0.46,
      0.32,
      0.54,
      0.35,
      0.18,
      0.43,
      0.28,
      0.14,
      0.21
    ]
  },
  {
    "type": "club",
    "variant": "club-oval",
    "title": "NYC Photo Club",
    "meta": "127 MEMBERS",
    "footer": "$8 / MONTH · JOIN",
    "compactText": "$8 / MONTH · JOIN"
  },
  {
    "type": "club",
    "variant": "club-member",
    "title": "Sunday Readers",
    "meta": "A PLACE FOR GOOD BOOKS",
    "footer": "FREE · 32 MEMBERS",
    "compactText": "FREE · 32 MEMBERS"
  },
  {
    "type": "club",
    "variant": "club-tag",
    "title": "Studio Circle",
    "meta": "MAKE SOMETHING TOGETHER",
    "footer": "$12 / MONTH · JOIN",
    "compactText": "$12 / MONTH · JOIN"
  },
  {
    "type": "event",
    "variant": "event-ticket",
    "title": "After Hours",
    "meta": "BROOKLYN · LIVE MUSIC",
    "footer": "7 PM · $12 ENTRY",
    "sideTop": "SEP",
    "sideMain": "26",
    "compactText": "7 PM · $12 ENTRY"
  },
  {
    "type": "event",
    "variant": "event-screening",
    "title": "Sunday Cinema",
    "meta": "ONE FILM. GOOD COMPANY.",
    "footer": "7 PM · $10 ENTRY",
    "sideTop": "OCT",
    "sideMain": "02",
    "compactText": "7 PM · $10 ENTRY"
  },
  {
    "type": "event",
    "variant": "event-postal",
    "title": "Neighborhood Fest",
    "meta": "FOOD · MUSIC · LOCAL PEOPLE",
    "footer": "OCT 03 · 12 PM · FREE",
    "compactText": "OCT 03 · 12 PM · FREE"
  },
  {
    "type": "meetup",
    "variant": "meetup-note",
    "title": "Photo Walk",
    "meta": "DUMBO · 8 / 12 GOING",
    "footer": "SEP 27 · 2 PM · FREE",
    "compactText": "SEP 27 · 2 PM · DUMBO"
  },
  {
    "type": "meetup",
    "variant": "meetup-fold",
    "title": "Coffee & Company",
    "meta": "EAST VILLAGE · NEW YORK",
    "footer": "SAT · 11 AM · 6 SPOTS",
    "compactText": "SAT · 11 AM · 6 SPOTS"
  },
  {
    "type": "meetup",
    "variant": "meetup-route",
    "title": "Study Together",
    "meta": "BRING YOUR NOTEBOOK",
    "footer": "SEP 30 · 4 PM · BRONX",
    "compactText": "SEP 30 · 4 PM · BRONX"
  },
  {
    "type": "deal",
    "variant": "deal-coupon",
    "title": "15% OFF",
    "meta": "CAFÉ LUNA",
    "footer": "MIN. SPEND $20",
    "sideMain": "VIEW",
    "sideBottom": "OFFER",
    "compactText": "CAFÉ LUNA · $20 MIN."
  },
  {
    "type": "deal",
    "variant": "deal-cashback",
    "title": "$4 BACK",
    "meta": "JOE’S PIZZA",
    "footer": "SPEND $20+ · SCAN RECEIPT",
    "compactText": "JOE’S PIZZA · $20 MIN."
  },
  {
    "type": "deal",
    "variant": "deal-drop",
    "title": "FREE DRINK",
    "meta": "CAFÉ LUNA",
    "footer": "WITH A $15+ PURCHASE",
    "sideMain": "VIEW",
    "compactText": "CAFÉ LUNA · $15 MIN."
  }
];
