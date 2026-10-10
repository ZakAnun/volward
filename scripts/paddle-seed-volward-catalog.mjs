#!/usr/bin/env node
/**
 * Create one Paddle product + four one-time USD prices for Volward credit packs.
 *
 * NOT idempotent: every run POSTs a new product and four new pri_* IDs.
 * Do not run against an account that already has the Volward catalog
 * (sandbox already has pri_01m4j8rh…). Use the dashboard/MCP to archive
 * or update existing prices instead.
 *
 * List USD (cents) is authoritative — keep in sync with migration 013 / pricing.rs.
 *
 *   PADDLE_API_KEY=pdl_sdbx_apikey_... PADDLE_ENVIRONMENT=sandbox \
 *     node scripts/paddle-seed-volward-catalog.mjs
 */
const CNY_YUAN_PER_USD = 7.2;

const PACKS = [
  { id: "trial", usd_cents: 149, credits: 100, description: "Volward 100 credits · trial" },
  { id: "standard", usd_cents: 299, credits: 220, description: "Volward 220 credits" },
  { id: "plus", usd_cents: 649, credits: 550, description: "Volward 550 credits" },
  { id: "max", usd_cents: 1299, credits: 1200, description: "Volward 1200 credits" },
].map((p) => ({
  ...p,
  cny_fen: Math.round((p.usd_cents / 100) * CNY_YUAN_PER_USD * 100),
}));

const apiKey = process.env.PADDLE_API_KEY;
if (!apiKey) {
  console.error("Set PADDLE_API_KEY (sandbox: pdl_sdbx_..., live: pdl_live_...).");
  process.exit(1);
}

const envName = (process.env.PADDLE_ENVIRONMENT ?? "sandbox").toLowerCase();
const apiBase =
  envName === "live" || envName === "production"
    ? "https://api.paddle.com"
    : "https://sandbox-api.paddle.com";

async function paddlePost(path, body) {
  const res = await fetch(`${apiBase}${path}`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  if (!res.ok) {
    throw new Error(`Paddle ${path} ${res.status}: ${text}`);
  }
  return JSON.parse(text).data;
}

async function main() {
  const product = await paddlePost("/products", {
    name: "Volward Credits",
    tax_category: "digital-goods",
    description: "One-time credit packs for Volward disk analysis.",
  });

  const priceIds = {};
  for (const pack of PACKS) {
    const price = await paddlePost("/prices", {
      product_id: product.id,
      description: pack.description,
      unit_price: {
        amount: String(pack.usd_cents),
        currency_code: "USD",
      },
    });
    priceIds[pack.id] = price.id;
  }

  console.log(
    JSON.stringify(
      { product_id: product.id, prices: priceIds, packs: PACKS },
      null,
      2,
    ),
  );
  console.log("\n-- SQLite (platform.db):\n");
  for (const [packId, priId] of Object.entries(priceIds)) {
    console.log(
      `UPDATE packs SET provider_product_id = '${priId}' WHERE id = '${packId}';`,
    );
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
