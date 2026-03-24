CREATE TABLE ocdata (jurisdiction_code,all_attributes,registered_address,industry_codes,company_number,incorporation_date,name,current_status,company_type,retrieved_at,dissolution_date, identifiers, branch, UNIQUE (company_number));
CREATE TABLE IF NOT EXISTS swvariables (name,value_blob,type, UNIQUE (name));
CREATE TABLE unhandled_response_company_numbers (company_number UNIQUE, error_details);
