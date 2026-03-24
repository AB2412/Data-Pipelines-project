CREATE TABLE ocdata (jurisdiction_code,all_attributes,registered_address,officers,industry_codes,headquarters_address,incorporation_date,company_type,name,company_number,retrieved_at, dissolution_date, branch, UNIQUE (company_number));
CREATE TABLE IF NOT EXISTS swvariables (name,value_blob,type, UNIQUE (name));
