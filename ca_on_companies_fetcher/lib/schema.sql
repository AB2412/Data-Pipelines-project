CREATE TABLE IF NOT EXISTS ocdata (company_number,retrieved_at,incorporation_date,dissolution_date,industry_code,registered_address,headquarters_address,jurisdiction_code,all_attributes,name,current_status, UNIQUE (company_number));
CREATE TABLE IF NOT EXISTS registry_queue (uid,sampled_date,company_type,UNIQUE (uid));
CREATE TABLE IF NOT EXISTS failed_search_queue (search_number,sampled_date,UNIQUE (search_number));

CREATE UNIQUE INDEX IF NOT EXISTS company_number ON ocdata (company_number);
CREATE UNIQUE INDEX IF NOT EXISTS uid ON registry_queue (uid);
