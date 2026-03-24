CREATE TABLE swvariables (name,value_blob,type, UNIQUE (name));
CREATE TABLE ocdata (jurisdiction_code,all_attributes,filings,officers,headquarters_address,mailing_address,company_number,company_type,current_status,name,incorporation_date,retrieved_at, branch, registered_address, alternative_names, UNIQUE (company_number));
CREATE UNIQUE INDEX name ON swvariables (name);
CREATE UNIQUE INDEX company_number ON ocdata (company_number);
