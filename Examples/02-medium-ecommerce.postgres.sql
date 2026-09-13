-- =====================================================================
-- 02 · Medium · Full-featured E-commerce
-- Dialect: PostgreSQL 15+
-- Tables:  ~50
-- Purpose: A realistic e-commerce backend: catalog (products, variants,
--          categories, brands), customers, orders (cart, checkout,
--          shipments, returns), payments, promotions, reviews, warehouse
--          & inventory, wishlists, and an integration/audit layer.
-- =====================================================================

BEGIN;

-- =========================
-- 1. IDENTITY & ADDRESSES
-- =========================

CREATE TABLE customers (
  id             BIGSERIAL PRIMARY KEY,
  email          TEXT NOT NULL UNIQUE,
  password_hash  TEXT NOT NULL,
  first_name     TEXT,
  last_name      TEXT,
  phone          TEXT,
  is_guest       BOOLEAN NOT NULL DEFAULT false,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX customers_email_idx ON customers(email);

CREATE TABLE customer_sessions (
  id         BIGSERIAL PRIMARY KEY,
  customer_id BIGINT NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  token_hash TEXT   NOT NULL UNIQUE,
  ip_address INET,
  user_agent TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX customer_sessions_customer_id_idx ON customer_sessions(customer_id);

CREATE TABLE countries (
  code     CHAR(2) PRIMARY KEY,
  name     TEXT NOT NULL,
  currency CHAR(3) NOT NULL
);

CREATE TABLE addresses (
  id             BIGSERIAL PRIMARY KEY,
  customer_id    BIGINT NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  label          TEXT,
  line1          TEXT NOT NULL,
  line2          TEXT,
  city           TEXT NOT NULL,
  region         TEXT,
  postal_code    TEXT,
  country_code   CHAR(2) NOT NULL REFERENCES countries(code),
  phone          TEXT,
  is_default_ship BOOLEAN NOT NULL DEFAULT false,
  is_default_bill BOOLEAN NOT NULL DEFAULT false,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX addresses_customer_id_idx ON addresses(customer_id);

-- =========================
-- 2. CATALOG
-- =========================

CREATE TABLE categories (
  id         BIGSERIAL PRIMARY KEY,
  parent_id  BIGINT REFERENCES categories(id) ON DELETE SET NULL,
  slug       TEXT NOT NULL UNIQUE,
  name       TEXT NOT NULL,
  position   INT  NOT NULL DEFAULT 0,
  is_active  BOOLEAN NOT NULL DEFAULT true
);
CREATE INDEX categories_parent_id_idx ON categories(parent_id);

CREATE TABLE brands (
  id      BIGSERIAL PRIMARY KEY,
  slug    TEXT NOT NULL UNIQUE,
  name    TEXT NOT NULL,
  website TEXT
);

CREATE TABLE products (
  id           BIGSERIAL PRIMARY KEY,
  brand_id     BIGINT REFERENCES brands(id),
  category_id  BIGINT REFERENCES categories(id),
  slug         TEXT NOT NULL UNIQUE,
  name         TEXT NOT NULL,
  description  TEXT,
  base_price_cents INTEGER NOT NULL CHECK (base_price_cents >= 0),
  status       TEXT NOT NULL CHECK (status IN ('draft','published','archived')),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX products_brand_id_idx    ON products(brand_id);
CREATE INDEX products_category_id_idx ON products(category_id);
CREATE INDEX products_status_idx      ON products(status);

CREATE TABLE product_options (
  id         BIGSERIAL PRIMARY KEY,
  product_id BIGINT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  name       TEXT   NOT NULL,      -- e.g. "Size", "Color"
  position   INT    NOT NULL DEFAULT 0
);
CREATE INDEX product_options_product_id_idx ON product_options(product_id);

CREATE TABLE product_option_values (
  id         BIGSERIAL PRIMARY KEY,
  option_id  BIGINT NOT NULL REFERENCES product_options(id) ON DELETE CASCADE,
  value      TEXT   NOT NULL,      -- e.g. "M", "Blue"
  position   INT    NOT NULL DEFAULT 0
);
CREATE INDEX product_option_values_option_id_idx ON product_option_values(option_id);

CREATE TABLE product_variants (
  id             BIGSERIAL PRIMARY KEY,
  product_id     BIGINT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  sku            TEXT   NOT NULL UNIQUE,
  price_cents    INTEGER NOT NULL CHECK (price_cents >= 0),
  weight_grams   INTEGER,
  barcode        TEXT,
  is_active      BOOLEAN NOT NULL DEFAULT true,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX product_variants_product_id_idx ON product_variants(product_id);

CREATE TABLE variant_option_values (
  variant_id  BIGINT NOT NULL REFERENCES product_variants(id)     ON DELETE CASCADE,
  option_id   BIGINT NOT NULL REFERENCES product_options(id)      ON DELETE CASCADE,
  value_id    BIGINT NOT NULL REFERENCES product_option_values(id) ON DELETE CASCADE,
  PRIMARY KEY (variant_id, option_id)
);

CREATE TABLE product_images (
  id          BIGSERIAL PRIMARY KEY,
  product_id  BIGINT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  variant_id  BIGINT REFERENCES product_variants(id) ON DELETE SET NULL,
  url         TEXT   NOT NULL,
  alt         TEXT,
  position    INT    NOT NULL DEFAULT 0
);
CREATE INDEX product_images_product_id_idx ON product_images(product_id);
CREATE INDEX product_images_variant_id_idx ON product_images(variant_id);

CREATE TABLE tags (
  id   BIGSERIAL PRIMARY KEY,
  slug TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL
);
CREATE TABLE product_tags (
  product_id BIGINT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  tag_id     BIGINT NOT NULL REFERENCES tags(id)     ON DELETE CASCADE,
  PRIMARY KEY (product_id, tag_id)
);

-- =========================
-- 3. INVENTORY & WAREHOUSING
-- =========================

CREATE TABLE warehouses (
  id       BIGSERIAL PRIMARY KEY,
  code     TEXT NOT NULL UNIQUE,
  name     TEXT NOT NULL,
  address_id BIGINT REFERENCES addresses(id),
  is_active BOOLEAN NOT NULL DEFAULT true
);
CREATE INDEX warehouses_address_id_idx ON warehouses(address_id);

CREATE TABLE inventory_levels (
  id           BIGSERIAL PRIMARY KEY,
  warehouse_id BIGINT NOT NULL REFERENCES warehouses(id)      ON DELETE CASCADE,
  variant_id   BIGINT NOT NULL REFERENCES product_variants(id) ON DELETE CASCADE,
  on_hand      INTEGER NOT NULL DEFAULT 0 CHECK (on_hand >= 0),
  reserved     INTEGER NOT NULL DEFAULT 0 CHECK (reserved >= 0),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (warehouse_id, variant_id)
);

CREATE TABLE stock_movements (
  id             BIGSERIAL PRIMARY KEY,
  warehouse_id   BIGINT NOT NULL REFERENCES warehouses(id),
  variant_id     BIGINT NOT NULL REFERENCES product_variants(id),
  delta          INTEGER NOT NULL,
  reason         TEXT NOT NULL, -- e.g. 'receipt','sale','return','adjustment'
  reference_type TEXT,          -- polymorphic (order_id / grn_id ...)
  reference_id   BIGINT,
  created_by     BIGINT REFERENCES customers(id),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX stock_movements_warehouse_id_idx ON stock_movements(warehouse_id);
CREATE INDEX stock_movements_variant_id_idx   ON stock_movements(variant_id);
CREATE INDEX stock_movements_created_by_idx   ON stock_movements(created_by);

-- =========================
-- 4. CART & CHECKOUT
-- =========================

CREATE TABLE carts (
  id           BIGSERIAL PRIMARY KEY,
  customer_id  BIGINT REFERENCES customers(id) ON DELETE CASCADE,
  session_key  TEXT   UNIQUE,  -- for guest carts
  currency     CHAR(3) NOT NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX carts_customer_id_idx ON carts(customer_id);

CREATE TABLE cart_items (
  id         BIGSERIAL PRIMARY KEY,
  cart_id    BIGINT  NOT NULL REFERENCES carts(id) ON DELETE CASCADE,
  variant_id BIGINT  NOT NULL REFERENCES product_variants(id),
  quantity   INTEGER NOT NULL CHECK (quantity > 0),
  unit_price_cents INTEGER NOT NULL,
  UNIQUE (cart_id, variant_id)
);
CREATE INDEX cart_items_cart_id_idx    ON cart_items(cart_id);
CREATE INDEX cart_items_variant_id_idx ON cart_items(variant_id);

-- =========================
-- 5. ORDERS, SHIPMENTS, RETURNS
-- =========================

CREATE TABLE orders (
  id              BIGSERIAL PRIMARY KEY,
  customer_id     BIGINT NOT NULL REFERENCES customers(id),
  cart_id         BIGINT REFERENCES carts(id),
  ship_address_id BIGINT REFERENCES addresses(id),
  bill_address_id BIGINT REFERENCES addresses(id),
  order_number    TEXT NOT NULL UNIQUE,
  currency        CHAR(3) NOT NULL,
  subtotal_cents  INTEGER NOT NULL,
  discount_cents  INTEGER NOT NULL DEFAULT 0,
  tax_cents       INTEGER NOT NULL DEFAULT 0,
  shipping_cents  INTEGER NOT NULL DEFAULT 0,
  total_cents     INTEGER NOT NULL,
  status          TEXT NOT NULL CHECK (status IN ('draft','pending','paid','fulfilled','cancelled','refunded')),
  placed_at       TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX orders_customer_id_idx    ON orders(customer_id);
CREATE INDEX orders_status_idx         ON orders(status);
CREATE INDEX orders_placed_at_idx      ON orders(placed_at);
CREATE INDEX orders_ship_address_id_idx ON orders(ship_address_id);
CREATE INDEX orders_bill_address_id_idx ON orders(bill_address_id);

CREATE TABLE order_items (
  id                BIGSERIAL PRIMARY KEY,
  order_id          BIGINT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  variant_id        BIGINT NOT NULL REFERENCES product_variants(id),
  quantity          INTEGER NOT NULL CHECK (quantity > 0),
  unit_price_cents  INTEGER NOT NULL,
  tax_cents         INTEGER NOT NULL DEFAULT 0,
  discount_cents    INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX order_items_order_id_idx   ON order_items(order_id);
CREATE INDEX order_items_variant_id_idx ON order_items(variant_id);

CREATE TABLE order_events (
  id         BIGSERIAL PRIMARY KEY,
  order_id   BIGINT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  event_type TEXT NOT NULL,
  payload    JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX order_events_order_id_idx ON order_events(order_id);

CREATE TABLE shipments (
  id             BIGSERIAL PRIMARY KEY,
  order_id       BIGINT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  warehouse_id   BIGINT REFERENCES warehouses(id),
  carrier        TEXT,
  tracking_number TEXT,
  status         TEXT NOT NULL CHECK (status IN ('pending','shipped','delivered','failed')),
  shipped_at     TIMESTAMPTZ,
  delivered_at   TIMESTAMPTZ,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX shipments_order_id_idx     ON shipments(order_id);
CREATE INDEX shipments_warehouse_id_idx ON shipments(warehouse_id);

CREATE TABLE shipment_items (
  id            BIGSERIAL PRIMARY KEY,
  shipment_id   BIGINT NOT NULL REFERENCES shipments(id)    ON DELETE CASCADE,
  order_item_id BIGINT NOT NULL REFERENCES order_items(id)  ON DELETE CASCADE,
  quantity      INTEGER NOT NULL CHECK (quantity > 0)
);
CREATE INDEX shipment_items_shipment_id_idx   ON shipment_items(shipment_id);
CREATE INDEX shipment_items_order_item_id_idx ON shipment_items(order_item_id);

CREATE TABLE returns (
  id           BIGSERIAL PRIMARY KEY,
  order_id     BIGINT NOT NULL REFERENCES orders(id),
  status       TEXT NOT NULL CHECK (status IN ('requested','approved','received','closed','rejected')),
  reason       TEXT,
  requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  closed_at    TIMESTAMPTZ
);
CREATE INDEX returns_order_id_idx ON returns(order_id);

CREATE TABLE return_items (
  id            BIGSERIAL PRIMARY KEY,
  return_id     BIGINT NOT NULL REFERENCES returns(id)      ON DELETE CASCADE,
  order_item_id BIGINT NOT NULL REFERENCES order_items(id),
  quantity      INTEGER NOT NULL CHECK (quantity > 0),
  restock       BOOLEAN NOT NULL DEFAULT true
);
CREATE INDEX return_items_return_id_idx     ON return_items(return_id);
CREATE INDEX return_items_order_item_id_idx ON return_items(order_item_id);

-- =========================
-- 6. PAYMENTS
-- =========================

CREATE TABLE payment_methods (
  id          BIGSERIAL PRIMARY KEY,
  customer_id BIGINT NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  kind        TEXT NOT NULL CHECK (kind IN ('card','wallet','bank','cash')),
  provider    TEXT NOT NULL,   -- 'stripe','paypal',...
  provider_token TEXT NOT NULL,
  last4       CHAR(4),
  expires_at  DATE,
  is_default  BOOLEAN NOT NULL DEFAULT false,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX payment_methods_customer_id_idx ON payment_methods(customer_id);

CREATE TABLE payments (
  id                BIGSERIAL PRIMARY KEY,
  order_id          BIGINT NOT NULL REFERENCES orders(id),
  payment_method_id BIGINT REFERENCES payment_methods(id),
  provider          TEXT NOT NULL,
  provider_ref      TEXT UNIQUE,
  amount_cents      INTEGER NOT NULL,
  currency          CHAR(3) NOT NULL,
  status            TEXT NOT NULL CHECK (status IN ('pending','authorized','captured','failed','refunded')),
  authorized_at     TIMESTAMPTZ,
  captured_at       TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX payments_order_id_idx           ON payments(order_id);
CREATE INDEX payments_payment_method_id_idx  ON payments(payment_method_id);

CREATE TABLE refunds (
  id           BIGSERIAL PRIMARY KEY,
  payment_id   BIGINT NOT NULL REFERENCES payments(id) ON DELETE CASCADE,
  return_id    BIGINT REFERENCES returns(id),
  amount_cents INTEGER NOT NULL,
  reason       TEXT,
  processed_at TIMESTAMPTZ,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX refunds_payment_id_idx ON refunds(payment_id);
CREATE INDEX refunds_return_id_idx  ON refunds(return_id);

-- =========================
-- 7. PROMOTIONS
-- =========================

CREATE TABLE promotions (
  id          BIGSERIAL PRIMARY KEY,
  code        TEXT UNIQUE,
  name        TEXT NOT NULL,
  discount_kind TEXT NOT NULL CHECK (discount_kind IN ('percent','fixed','free_shipping')),
  amount      NUMERIC(12,2) NOT NULL,
  starts_at   TIMESTAMPTZ,
  ends_at     TIMESTAMPTZ,
  max_uses    INTEGER,
  min_order_cents INTEGER,
  is_active   BOOLEAN NOT NULL DEFAULT true
);

CREATE TABLE promotion_applications (
  id           BIGSERIAL PRIMARY KEY,
  promotion_id BIGINT NOT NULL REFERENCES promotions(id) ON DELETE CASCADE,
  order_id     BIGINT NOT NULL REFERENCES orders(id)     ON DELETE CASCADE,
  amount_cents INTEGER NOT NULL,
  applied_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (promotion_id, order_id)
);
CREATE INDEX promotion_applications_order_id_idx ON promotion_applications(order_id);

CREATE TABLE promotion_products (
  promotion_id BIGINT NOT NULL REFERENCES promotions(id) ON DELETE CASCADE,
  product_id   BIGINT NOT NULL REFERENCES products(id)   ON DELETE CASCADE,
  PRIMARY KEY (promotion_id, product_id)
);

-- =========================
-- 8. REVIEWS & WISHLIST
-- =========================

CREATE TABLE reviews (
  id          BIGSERIAL PRIMARY KEY,
  product_id  BIGINT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  customer_id BIGINT NOT NULL REFERENCES customers(id),
  rating      INT NOT NULL CHECK (rating BETWEEN 1 AND 5),
  title       TEXT,
  body        TEXT,
  is_verified BOOLEAN NOT NULL DEFAULT false,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX reviews_product_id_idx  ON reviews(product_id);
CREATE INDEX reviews_customer_id_idx ON reviews(customer_id);

CREATE TABLE review_votes (
  review_id   BIGINT NOT NULL REFERENCES reviews(id)   ON DELETE CASCADE,
  customer_id BIGINT NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  is_helpful  BOOLEAN NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (review_id, customer_id)
);

CREATE TABLE wishlists (
  id          BIGSERIAL PRIMARY KEY,
  customer_id BIGINT NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  name        TEXT NOT NULL DEFAULT 'Wishlist',
  is_public   BOOLEAN NOT NULL DEFAULT false,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX wishlists_customer_id_idx ON wishlists(customer_id);

CREATE TABLE wishlist_items (
  wishlist_id BIGINT NOT NULL REFERENCES wishlists(id)         ON DELETE CASCADE,
  variant_id  BIGINT NOT NULL REFERENCES product_variants(id)  ON DELETE CASCADE,
  added_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (wishlist_id, variant_id)
);

-- =========================
-- 9. NOTIFICATIONS & AUDIT
-- =========================

CREATE TABLE notification_templates (
  id      BIGSERIAL PRIMARY KEY,
  key     TEXT NOT NULL UNIQUE,
  subject TEXT NOT NULL,
  body_md TEXT NOT NULL
);

CREATE TABLE notifications (
  id           BIGSERIAL PRIMARY KEY,
  customer_id  BIGINT NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  template_id  BIGINT REFERENCES notification_templates(id),
  channel      TEXT NOT NULL CHECK (channel IN ('email','sms','push')),
  payload      JSONB NOT NULL DEFAULT '{}'::jsonb,
  sent_at      TIMESTAMPTZ,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX notifications_customer_id_idx ON notifications(customer_id);
CREATE INDEX notifications_template_id_idx ON notifications(template_id);

CREATE TABLE webhooks (
  id         BIGSERIAL PRIMARY KEY,
  url        TEXT NOT NULL,
  secret     TEXT NOT NULL,
  event_kind TEXT NOT NULL,
  is_active  BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE webhook_deliveries (
  id            BIGSERIAL PRIMARY KEY,
  webhook_id    BIGINT NOT NULL REFERENCES webhooks(id) ON DELETE CASCADE,
  status_code   INT,
  response_body TEXT,
  attempted_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX webhook_deliveries_webhook_id_idx ON webhook_deliveries(webhook_id);

CREATE TABLE audit_events (
  id          BIGSERIAL PRIMARY KEY,
  actor_type  TEXT NOT NULL CHECK (actor_type IN ('customer','staff','system')),
  actor_id    BIGINT,
  entity      TEXT NOT NULL,
  entity_id   BIGINT NOT NULL,
  action      TEXT NOT NULL,
  before      JSONB,
  after       JSONB,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX audit_events_entity_idx ON audit_events(entity, entity_id);

CREATE TABLE feature_flags (
  key         TEXT PRIMARY KEY,
  is_enabled  BOOLEAN NOT NULL DEFAULT false,
  description TEXT,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMIT;
