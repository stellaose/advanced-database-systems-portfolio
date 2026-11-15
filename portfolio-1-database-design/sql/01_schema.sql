DROP SCHEMA IF EXISTS konga CASCADE;
CREATE SCHEMA konga;
SET search_path TO konga;


CREATE customers(
  customer_id VARCHAR(36) PRIMARY KEY
    DEFAULT gen_random_uuid()::text,
  email_address VARCHAR(255) NOT NULL UNIQUE,
  phone_number VARCHAR(20) NOT NULL UNIQUE,
  full_name VARCHAR(255) NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
      created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
  CONSTRAINT chk_customers_email_address CHECK (position('@' IN email_address) > 1)

  
)