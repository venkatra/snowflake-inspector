--
--  This script is to be executed when there is a need for doing analyzes using the snowflake inspector tool. The
-- script essentially takes/copies data from various show commands and views of snowflake.account_usage schema (conditional).
--
--  Since there are various objects that needs to be created, the script needs to be executed by securityadmin
--  roles.
--

-- Create
use role securityadmin;

--Copy users"SNOWFLAKE"."INFORMATION_SCHEMA"."ENABLED_ROLES"
SHOW users;
create or replace transient table blog_db.snwflktool.dbusers as
    select "login_name" ,"disabled" ,"snowflake_lock"
    from table( RESULT_SCAN ( last_query_id()) );
GRANT SELECT ON TABLE blog_db.snwflktool.dbusers TO ROLE SNWFLK_INSPECTOR;
