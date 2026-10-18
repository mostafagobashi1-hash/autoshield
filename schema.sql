-- AutoShield starter schema (PostgreSQL)
-- Currency: EGP. One branch initially; branch_id can be added to all operational tables when multi-branch is enabled.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TYPE work_order_status AS ENUM (
  'new','awaiting_approval','queued','in_progress','quality_check',
  'ready_for_delivery','delivered','on_hold','cancelled'
);

CREATE TABLE roles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT UNIQUE NOT NULL,
  permissions JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  role_id UUID NOT NULL REFERENCES roles(id),
  full_name TEXT NOT NULL,
  email TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE customers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  full_name TEXT NOT NULL,
  phone TEXT NOT NULL,
  email TEXT,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX customers_phone_idx ON customers(phone);

CREATE TABLE vehicles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id UUID NOT NULL REFERENCES customers(id),
  plate_number TEXT,
  make TEXT,
  model TEXT,
  model_year INTEGER,
  color TEXT,
  vin TEXT,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX vehicles_plate_idx ON vehicles(plate_number);

CREATE TABLE services (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT UNIQUE NOT NULL,
  description TEXT,
  default_price NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK(default_price >= 0),
  estimated_minutes INTEGER,
  is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE products (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sku TEXT UNIQUE,
  name TEXT NOT NULL,
  unit TEXT NOT NULL, -- roll, meter, piece, bottle, liter
  minimum_quantity NUMERIC(12,3) NOT NULL DEFAULT 0 CHECK(minimum_quantity >= 0),
  is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE suppliers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  phone TEXT,
  email TEXT,
  notes TEXT
);

CREATE TABLE work_orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_number BIGSERIAL UNIQUE,
  vehicle_id UUID NOT NULL REFERENCES vehicles(id),
  status work_order_status NOT NULL DEFAULT 'new',
  technician_notes TEXT,
  customer_notes TEXT,
  assigned_to UUID REFERENCES users(id),
  due_at TIMESTAMPTZ,
  accepted_at TIMESTAMPTZ,
  delivered_at TIMESTAMPTZ,
  created_by UUID REFERENCES users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE work_order_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  work_order_id UUID NOT NULL REFERENCES work_orders(id) ON DELETE RESTRICT,
  service_id UUID REFERENCES services(id),
  description TEXT NOT NULL,
  quantity NUMERIC(12,3) NOT NULL DEFAULT 1 CHECK(quantity > 0),
  unit_price NUMERIC(12,2) NOT NULL CHECK(unit_price >= 0),
  discount NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK(discount >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK(discount <= quantity * unit_price)
);

CREATE TABLE work_assignments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  work_order_id UUID NOT NULL REFERENCES work_orders(id) ON DELETE RESTRICT,
  user_id UUID NOT NULL REFERENCES users(id),
  assignment_role TEXT,
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  notes TEXT
);

CREATE TABLE inventory_movements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id UUID NOT NULL REFERENCES products(id),
  work_order_id UUID REFERENCES work_orders(id),
  supplier_id UUID REFERENCES suppliers(id),
  movement_type TEXT NOT NULL CHECK(movement_type IN ('opening','purchase','consumption','waste','adjustment','return')),
  quantity_delta NUMERIC(12,3) NOT NULL CHECK(quantity_delta <> 0),
  unit_cost NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK(unit_cost >= 0),
  note TEXT,
  created_by UUID REFERENCES users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX inventory_product_date_idx ON inventory_movements(product_id, created_at);

CREATE TABLE invoices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_number BIGSERIAL UNIQUE,
  work_order_id UUID NOT NULL REFERENCES work_orders(id) ON DELETE RESTRICT,
  subtotal NUMERIC(12,2) NOT NULL CHECK(subtotal >= 0),
  discount NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK(discount >= 0),
  tax NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK(tax >= 0),
  total NUMERIC(12,2) NOT NULL CHECK(total >= 0),
  status TEXT NOT NULL DEFAULT 'unpaid' CHECK(status IN ('unpaid','partial','paid','void')),
  issued_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID REFERENCES users(id),
  CHECK(total = subtotal - discount + tax)
);

CREATE TABLE payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_id UUID NOT NULL REFERENCES invoices(id) ON DELETE RESTRICT,
  amount NUMERIC(12,2) NOT NULL CHECK(amount > 0),
  method TEXT NOT NULL CHECK(method IN ('cash','card','bank_transfer','wallet','other')),
  reference TEXT,
  received_by UUID REFERENCES users(id),
  received_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE expenses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  category TEXT NOT NULL,
  description TEXT NOT NULL,
  amount NUMERIC(12,2) NOT NULL CHECK(amount > 0),
  paid_by UUID REFERENCES users(id),
  incurred_at DATE NOT NULL DEFAULT CURRENT_DATE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE warranties (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  work_order_item_id UUID NOT NULL REFERENCES work_order_items(id),
  warranty_number TEXT UNIQUE NOT NULL,
  start_date DATE NOT NULL,
  end_date DATE NOT NULL,
  terms TEXT,
  status TEXT NOT NULL DEFAULT 'active' CHECK(status IN ('active','expired','void')),
  CHECK(end_date >= start_date)
);

CREATE TABLE warranty_claims (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  warranty_id UUID NOT NULL REFERENCES warranties(id),
  reported_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  complaint TEXT NOT NULL,
  inspection_notes TEXT,
  resolution TEXT,
  status TEXT NOT NULL DEFAULT 'open' CHECK(status IN ('open','inspecting','approved','rejected','resolved'))
);

CREATE TABLE attachments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  work_order_id UUID NOT NULL REFERENCES work_orders(id),
  file_url TEXT NOT NULL,
  file_name TEXT NOT NULL,
  media_type TEXT,
  category TEXT NOT NULL CHECK(category IN ('intake','before','during','after','warranty','other')),
  uploaded_by UUID REFERENCES users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE audit_logs (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID REFERENCES users(id),
  action TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id UUID,
  details JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Suggested initial service seed data:
INSERT INTO services(name, description, default_price) VALUES
 ('PPF','Paint Protection Film',0),
 ('تظليل وعزل حراري','Window tint / heat rejection',0),
 ('نانو سيراميك','Ceramic coating',0),
 ('حماية الفوانيس','Headlight protection',0),
 ('تنظيف وتلميع','Cleaning and polishing',0)
ON CONFLICT(name) DO NOTHING;
