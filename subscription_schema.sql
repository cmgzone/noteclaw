-- Subscription System Schema Migration
-- Run this after admin_schema_update.sql

-- Create subscription_plans table
CREATE TABLE IF NOT EXISTS subscription_plans (
    id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    credits_per_month INTEGER NOT NULL,
    price DECIMAL(10, 2) NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    is_free_plan BOOLEAN DEFAULT FALSE,
    feature_access JSONB NOT NULL DEFAULT '{}',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create user_subscriptions table
CREATE TABLE IF NOT EXISTS user_subscriptions (
    id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    user_id TEXT REFERENCES users(id) ON DELETE CASCADE,
    plan_id TEXT REFERENCES subscription_plans(id),
    current_credits INTEGER DEFAULT 0,
    credits_consumed_this_month INTEGER DEFAULT 0,
    last_renewal_date TIMESTAMP,
    next_renewal_date TIMESTAMP,
    status VARCHAR(20) DEFAULT 'active', -- active, suspended, cancelled
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id)
);

-- Create credit_packages table
CREATE TABLE IF NOT EXISTS credit_packages (
    id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    name VARCHAR(100) NOT NULL,
    credits INTEGER NOT NULL,
    price DECIMAL(10, 2) NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create credit_transactions table
CREATE TABLE IF NOT EXISTS credit_transactions (
    id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    user_id TEXT REFERENCES users(id) ON DELETE CASCADE,
    amount INTEGER NOT NULL, -- positive for add, negative for consume
    transaction_type VARCHAR(50) NOT NULL, -- 'purchase', 'monthly_renewal', 'consumption', 'admin_adjustment'
    description TEXT,
    balance_after INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    metadata JSONB, -- store additional info like feature used, package purchased, etc.
    idempotency_key TEXT
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_credit_transactions_idempotency_key
    ON credit_transactions (idempotency_key)
    WHERE idempotency_key IS NOT NULL;

-- Create payment_transactions table
CREATE TABLE IF NOT EXISTS payment_transactions (
    id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    user_id TEXT REFERENCES users(id) ON DELETE CASCADE,
    package_id TEXT REFERENCES credit_packages(id),
    amount DECIMAL(10, 2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'USD',
    payment_method VARCHAR(50) DEFAULT 'paypal',
    payment_status VARCHAR(20) NOT NULL, -- 'pending', 'completed', 'failed', 'refunded'
    paypal_order_id VARCHAR(255),
    paypal_transaction_id VARCHAR(255),
    credits_granted INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    metadata JSONB
);

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_user_subscriptions_user_id ON user_subscriptions(user_id);
CREATE INDEX IF NOT EXISTS idx_credit_transactions_user_id ON credit_transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_payment_transactions_user_id ON payment_transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_payment_transactions_status ON payment_transactions(payment_status);

-- Create renewal function
CREATE OR REPLACE FUNCTION renew_monthly_credits()
RETURNS void AS $$
BEGIN
    UPDATE user_subscriptions us
    SET 
        current_credits = CASE 
            WHEN sp.is_free_plan THEN sp.credits_per_month -- Reset to plan amount (non-cumulative for free)
            ELSE us.current_credits + sp.credits_per_month -- Add to existing (cumulative for paid)
        END,
        credits_consumed_this_month = 0,
        last_renewal_date = CURRENT_TIMESTAMP,
        next_renewal_date = CURRENT_TIMESTAMP + INTERVAL '1 month',
        updated_at = CURRENT_TIMESTAMP
    FROM subscription_plans sp
    WHERE us.plan_id = sp.id
      AND us.status = 'active'
      AND us.next_renewal_date <= CURRENT_TIMESTAMP;
      
    -- Log renewal transactions
    INSERT INTO credit_transactions (user_id, amount, transaction_type, description, balance_after)
    SELECT 
        us.user_id,
        sp.credits_per_month,
        'monthly_renewal',
        'Monthly credit renewal for ' || sp.name,
        us.current_credits
    FROM user_subscriptions us
    JOIN subscription_plans sp ON us.plan_id = sp.id
    WHERE us.last_renewal_date >= CURRENT_TIMESTAMP - INTERVAL '1 minute';
END;
$$ LANGUAGE plpgsql;

-- Insert default free plan
INSERT INTO subscription_plans (name, description, credits_per_month, price, is_active, is_free_plan)
VALUES ('Free Plan', 'Free plan with 30 credits per month', 30, 0.00, TRUE, TRUE)
ON CONFLICT DO NOTHING;

-- Insert sample credit packages
INSERT INTO credit_packages (name, credits, price, is_active, description)
VALUES 
    ('Starter Pack', 100, 4.99, TRUE, 'Perfect for occasional users'),
    ('Popular Pack', 500, 19.99, TRUE, 'Best value for regular users'),
    ('Pro Pack', 1000, 34.99, TRUE, 'For power users')
ON CONFLICT DO NOTHING;

-- Auto-assign new users to free plan (trigger)
CREATE OR REPLACE FUNCTION assign_free_plan_to_new_user()
RETURNS TRIGGER AS $$
DECLARE
    free_plan_id TEXT;
BEGIN
    -- Get the free plan ID
    SELECT id INTO free_plan_id FROM subscription_plans WHERE is_free_plan = TRUE LIMIT 1;
    
    -- Create subscription for new user
    IF free_plan_id IS NOT NULL THEN
        INSERT INTO user_subscriptions (
            user_id, 
            plan_id, 
            current_credits, 
            last_renewal_date, 
            next_renewal_date
        )
        VALUES (
            NEW.id,
            free_plan_id,
            30, -- Initial credits
            CURRENT_TIMESTAMP,
            CURRENT_TIMESTAMP + INTERVAL '1 month'
        );
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger
DROP TRIGGER IF EXISTS trigger_assign_free_plan ON users;
CREATE TRIGGER trigger_assign_free_plan
    AFTER INSERT ON users
    FOR EACH ROW
    EXECUTE FUNCTION assign_free_plan_to_new_user();

-- Assign free plan to existing users who don't have a subscription
DO $$
DECLARE
    free_plan_id TEXT;
BEGIN
    SELECT id INTO free_plan_id FROM subscription_plans WHERE is_free_plan = TRUE LIMIT 1;
    
    IF free_plan_id IS NOT NULL THEN
        INSERT INTO user_subscriptions (user_id, plan_id, current_credits, last_renewal_date, next_renewal_date)
        SELECT 
            u.id,
            free_plan_id,
            30,
            CURRENT_TIMESTAMP,
            CURRENT_TIMESTAMP + INTERVAL '1 month'
        FROM users u
        WHERE NOT EXISTS (
            SELECT 1 FROM user_subscriptions us WHERE us.user_id = u.id
        );
    END IF;
END $$;

-- Migration complete!
SELECT 'Subscription schema migration completed successfully!' AS status;
