ALTER TABLE api_tokens DROP CONSTRAINT IF EXISTS valid_token_prefix;
ALTER TABLE api_tokens ADD CONSTRAINT valid_token_prefix CHECK (
  token_prefix LIKE 'nclaw_%' OR token_prefix LIKE 'nllm_%'
);
