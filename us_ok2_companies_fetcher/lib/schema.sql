CREATE TABLE ocdata (jurisdiction_code,all_attributes,registered_address,filings,officers,alternative_names,company_number,current_status,company_type,name,incorporation_date,dissolution_date,retrieved_at, total_shares, UNIQUE (company_number));
CREATE UNIQUE INDEX company_number ON ocdata (company_number);
