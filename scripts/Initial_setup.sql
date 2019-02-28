--
--  This script is for initial setup only. The script essentially creates the various snowflake objects
--  and grant permissions.
--
--  Since there are various objects that needs to be created, the script needs to be executed by securityadmin/sysadmin/accountadmin
--  roles.
--

use role securityadmin;

--Create the user to be used by the inspector app
-- CREATE USER SVCHMAPBLOGGER ... (hidden for security reasons)

-- Create a seperate role that will be granted to access this database/schema
CREATE OR REPLACE ROLE SNWFLK_INSPECTOR
    COMMENT = 'This role will be used by the inspector app to build visualization based on this snowflake account usage';

-- Grant the role to the user
-- GRANT ROLE SNWFLK_INSPECTOR TO USER <USER>;

-- Create the database where snapshot of various views/commands will be stored and eventually be used by the inspector tool
use role sysadmin;
create or replace schema blog_db.snwflktool;
grant all on schema blog_db.snwflktool to role securityadmin;
grant all on schema blog_db.snwflktool to role SNWFLK_INSPECTOR;

-- The following will enable the SNWFLK_INSPECTOR to read the snowflake.account_usage schema
use role accountadmin;
GRANT IMPORTED PRIVILEGES ON DATABASE snowflake TO ROLE SNWFLK_INSPECTOR;
