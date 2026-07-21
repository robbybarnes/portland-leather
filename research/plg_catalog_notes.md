# Portland Leather Goods — Catalog Research Notes

Scraped 2026-07-20 from https://www.portlandleathergoods.com/ via the Shopify
`products.json` endpoint (fetched with Firecrawl). Internal research data only;
not for redistribution — app release pending brand permission.

## Catalog shape

- The store is Shopify. `products.json?limit=250` returned the whole live
  catalog in one page: **252 products total** (page 2 returned only 2 extras).
- Curated selection captured in `plg_products.json`: **37 products across 9
  categories** (Tote 6, Crossbody Tote 4, Crossbody 6, Belt Bag / Sling 2,
  Backpack 4, Wallet 5, Cardholder 3, Belt 2, Accessory 5).
- Shopify `product_type` values are coarse (Shoulder Bag, Crossbody Bag, Pouch,
  Wallet, Keychain, Backpack, Belts, Purse, Sling Bag, Zip Wallet, Tray, etc.).
  "Tote" is NOT a product_type — totes are typed Shoulder Bag or Crossbody Bag,
  so category assignment in our JSON is manual, based on title/tags.
- Roughly a quarter of the catalog is **"'Almost Perfect'" (AP-prefixed
  product_type) seconds/outlet duplicates** of first-quality products at lower
  prices (e.g. `almost-perfect-crossbody-tote`). We excluded all AP listings,
  plus Clearance/Mystery Box/Gift Card/Hidden items.
- No hats found in the current catalog; accessories skew toward keychains,
  tassels, pouches, trinket trays, straps, leather care, and canvas organizers.

## How sizes work (important for the app data model)

Two mechanisms coexist:

1. **Size as a variant option** (most common): products carry a `Size` option
   alongside `Color` (and sometimes `Style`). Examples: Leather Tote Bag
   (Small/Medium/Large/Oversized), August & Montana Totes (Medium/Large),
   Circle Crossbody, Bucket Bag, Tote Backpack (Small/Large), Koala Sling
   (Small/Medium/Large), Luxe Slim Wallet (Small/Large).
2. **Size baked into separate listings** (the Crossbody Tote family): "Mini
   Crossbody Tote", "Medium Crossbody Tote", and "Crossbody Tote" (the
   original) are three distinct products/handles, each with only Color + Style
   (Classic vs. Zipper) options. In our JSON these carry single-element `sizes`
   arrays (["Mini"], ["Medium"], ["Original"]) — an app should group them into
   one family. "Large Lola Zipper Crossbody Tote" is likewise a separate
   listing from "Lola Crossbody Tote".

A third pattern: a `Style` option distinguishes **Classic (open top) vs.
Zipper** closures on the tote lines (Leather Tote Bag, Montana Tote, Crossbody
Tote family) — Zipper costs ~$20 more.

### Master size list seen (across selected products)

- Bags/pouches: Mini, Small, Medium, Large, Original (Crossbody Tote family
  base), Oversized (Leather Tote Bag), Extra Large / Jumbo (Leather Tassel)
- Cardholders: Classic, Deluxe (Highlander)
- Belts: S, M, L, XL (women's); numeric 32–44 (men's)
- Leather care: 4oz, 8oz

## Colors

- 325 distinct color values across the full catalog; **202** across our 37
  selected products. Colorways rotate seasonally per product.
- Signature/staple colors that recur on most lines: **Honey, Cognac, Nutmeg,
  Coldbrew, Black, Chestnut, Sienna, Bone, Cobalt, Plum, Sea Glass, Chili Red,
  Sunshine, Grizzly, Merlot, Orchid, Koi**. (Note: "Espresso" was not present
  in the current catalog — closest staples are Coldbrew / Chocolate Brown /
  Java.)
- Some color values encode leather finish: "Pebbled Black" (raw value
  `Pebbled--black`), "Pebbled Bone", "Pink Suede", "Metallic Greench",
  "Wildflower *" (printed/embossed florals).
- A few products contained internal placeholder color values ("Misc"/"MISC");
  we stripped those.

## Leather types

- Baseline is smooth full-grain leather ("Smooth" in our JSON).
- **Pebbled**, **Suede**, and **Metallic** appear only as specific colorways
  within a product, not as separate products — so `leather_type` is recorded as
  e.g. "Smooth / Pebbled (varies by colorway)".
- No "Nubuck"/"Brushed" colorways were present in the current catalog snapshot.
- Non-leather items (canvas organizers, leather care) have `leather_type: null`.

## Data-quality caveats

- Prices are first-quality prices; the AP/'Almost Perfect' duplicates run
  substantially cheaper and would need separate handling if included.
- `price_min`/`price_max` span all variants (size and Classic-vs-Zipper style
  both move price).
- Descriptions are Shopify `body_html` bullet lists flattened to plain
  sentences and truncated to ~600 chars; some read as choppy bullet fragments.
- Color option values are marketing names only — no hex/swatch data in
  `products.json`; swatch images would need per-product page scraping.
- Image URLs are the first image on each product (usually the hero shot in the
  default colorway); append `&width=800` for resized CDN variants.
- Catalog rotates limited editions frequently; `scraped_at` matters.
