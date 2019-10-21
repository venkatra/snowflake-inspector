# Capturing USERS ,ROLES and GRANTS of SNOWFLAKE into a table

## Overview
If you have been snowflake for quiet some time, you would have realized
that retrieving the users, roles, grants is not direct. For some reason,
snowflake has not reflect these inside a table, not even as part of the
SNOWFLAKE.ACCOUNT_USAGE tables.

As we all the ways to get the list of users is via the show command.
Example to get the list of users, you would use the [Show Users](https://docs.snowflake.net/manuals/sql-reference/sql/show-users.html#show-users)
command. 

```sql
    SHOW USERS;
    SELECT * FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
``` 

Here are some slight inconvience:
 - To interact with the result of show command, you have to use the RESULT_SCAN function.
 - To get the full list of users/roles/grants the caller would have to be SECURITYADMIN role.
 - Other roles are not able to view the result. 
 
One scenario may be that you would like to develop a visualization say to: 
  - Determine which roles has the most populated user count.
  - Determine which privillege roles have user assigned to them.
  - Determine a mapping between roles,grants and users.
 
This write up outcomes with
 - script to create tables where the result will be stored
 - a store procedure which will capture the show command and writes into these tables.
 
 If interested follow along.
 
### Tables

We start of with creating the tables onto which the results of the show 
command would be stored. The table columns are exact as resulted from the 
SHOW commands.

#### Schema
 I would recomend you create these tables in a seperate schema. The schema
 should be acessible to only specific custom role (ex: AUDIT_ROLE), SECURITYADMIN 
 and ACCOUNTADMIN.

 For the sake of this walkthrough I am being relaxed and creating them in
 a common schema.
 
##### DBUSERS
 This table would store the list of users.
 
```sql
    CREATE OR REPLACE TABLE DBUSERS (
        NAME	VARCHAR,
        CREATED_ON	TIMESTAMP_LTZ,
        LOGIN_NAME	VARCHAR,
        DISPLAY_NAME	VARCHAR,
        FIRST_NAME	VARCHAR,
        LAST_NAME	VARCHAR,
        EMAIL	VARCHAR,
        MINS_TO_UNLOCK	VARCHAR,
        DAYS_TO_EXPIRY	VARCHAR,
        TCOMMENT	VARCHAR,
        DISABLED	VARCHAR,
        MUST_CHANGE_PASSWORD	VARCHAR,
        SNOWFLAKE_LOCK	VARCHAR,
        DEFAULT_WAREHOUSE	VARCHAR,
        DEFAULT_NAMESPACE	VARCHAR,
        DEFAULT_ROLE	VARCHAR,
        EXT_AUTHN_DUO	VARCHAR,
        EXT_AUTHN_UID	VARCHAR,
        MINS_TO_BYPASS_MFA	VARCHAR,
        OWNER	VARCHAR,
        LAST_SUCCESS_LOGIN	TIMESTAMP_LTZ,
        EXPIRES_AT_TIME	TIMESTAMP_LTZ,
        LOCKED_UNTIL_TIME	TIMESTAMP_LTZ,
        HAS_PASSWORD	VARCHAR,
        HAS_RSA_PUBLIC_KEY	VARCHAR,
        REFRESH_DATE TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
  )
  COMMENT = 'stores snapshot of current snowflake users and retain history of previous snapshots' ;
``` 
 
##### DBROLES
 This table would store the list of roles.
 
```sql
    CREATE OR REPLACE TABLE DBROLES (
      CREATED_ON	TIMESTAMP_LTZ,
      NAME	VARCHAR,
      IS_DEFAULT	VARCHAR,
      IS_CURRENT	VARCHAR,
      IS_INHERITED	VARCHAR,
      ASSIGNED_TO_USERS	NUMBER,
      GRANTED_TO_ROLES	NUMBER,
      GRANTED_ROLES	NUMBER,
      OWNER	VARCHAR,
      RCOMMENT	VARCHAR,
      REFRESH_DATE TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
    )
    COMMENT = 'stores snapshot of current snowflake roles and retain history of previous snapshots' ;
```
##### DBGRANTS
 This table would store the grants assigned to various users and roles.
 
```sql
    CREATE OR REPLACE TABLE DBGRANTS(
        CREATED_ON	TIMESTAMP_LTZ,
        PRIVILEGE	VARCHAR,
        GRANTED_ON	VARCHAR,
        NAME	VARCHAR,
        GRANTED_TO	VARCHAR,
        GRANTEE_NAME	VARCHAR,
        GRANT_OPTION	VARCHAR,
        GRANTED_BY	VARCHAR,
        REFRESH_DATE TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
   )
   COMMENT = 'stores snapshot of current grants and retain history of previous snapshots' ;
```

**NOTE :** Ensure that SECURITYADMIN have the privilleges to insert, update
and delete.

### Stored Procedures

The following set of stored procedures issues the corresponding show command
and captures the results into its corresponding table.

#### SNAPSHOTING USERS

```sql
CREATE OR REPLACE PROCEDURE SNAPSHOT_USERS()
 RETURNS VARCHAR
 LANGUAGE JAVASCRIPT
 COMMENT = 'Captures the snapshot of users and inserts the records into dbusers'
 EXECUTE AS CALLER
 AS
 $$
    var result = "SUCCESS";
    try {
        snowflake.execute( {sqlText: "TRUNCATE DBUSERS;"} );
        snowflake.execute( {sqlText: "show users;"} );

        var dbusers_tbl_sql = `
            insert into dbusers
              select * ,CURRENT_TIMESTAMP() 
              from table(result_scan(last_query_id()));
        `;
        snowflake.execute( {sqlText: dbusers_tbl_sql} );

    } catch (err)  {
        result =  "FAILED: Code: " + err.code + "\n  State: " + err.state;
        result += "\n  Message: " + err.message;
        result += "\nStack Trace:\n" + err.stackTraceTxt;
    }

    return result;
 $$
;
```

#### SNAPSHOTING ROLES

```sql
CREATE OR REPLACE PROCEDURE SNAPSHOT_ROLES()
 RETURNS VARCHAR
 LANGUAGE JAVASCRIPT
 COMMENT = 'Captures the snapshot of roles and inserts the records into dbroles'
 EXECUTE AS CALLER
 AS
 $$
    var result = "SUCCESS";
    try {
        snowflake.execute( {sqlText: "truncate table DBROLES;"} );
        snowflake.execute( {sqlText: "show roles;"} );

        var dbroles_tbl_sql = `
            insert into dbroles
                select *,CURRENT_TIMESTAMP()  
                from table(result_scan(last_query_id()));
            `;
        snowflake.execute( {sqlText: dbroles_tbl_sql} );
    } catch (err)  {
        result =  "FAILED: Code: " + err.code + "\n  State: " + err.state;
        result += "\n  Message: " + err.message;
        result += "\nStack Trace:\n" + err.stackTraceTxt;
    }

    return result;
 $$
;
``` 

#### SNAPSHOTING GRANTS

In the case of capturing grants it is a  little bit complex and iterative.
You have to capture of each individual database objects. In the case of
roles/users you have to iterate for each user/roles ,to capture the hierarchy.
The roles/users are retrieved from the DBUSERS & DBROLES table.

Luckily for you; i have the below code which does this. For now the below
captures :
 - Roles & Role relationships
 - Users & Role relationships
 
 For the other database objects like (tables, view, stages, external tables etc..)
 it is for you to expand for now).


```sql
CREATE OR REPLACE PROCEDURE SNAPSHOT_GRANTS()
 RETURNS VARCHAR
 LANGUAGE JAVASCRIPT
 COMMENT = 'Captures the snapshot of grants and inserts the records into dbgrants'
 EXECUTE AS CALLER
 AS
 $$
    function role_grants() {
        var obj_rs = snowflake.execute({sqlText: `
            SELECT NAME FROM DBROLES
            WHERE NAME NOT IN  ('ACCOUNTADMIN' ,'SECURITYADMIN' ,'SYSADMIN')
            AND (granted_to_roles > 0 or granted_roles > 0);
        `});

        while(obj_rs.next()) {
            snowflake.execute({sqlText: 'show grants to role "' + obj_rs.getColumnValue(1) + '" ;' });
            snowflake.execute( {sqlText:`
                insert into dbgrants
                    select *,CURRENT_TIMESTAMP()
                    from table(result_scan(last_query_id()))
                ;`
            });

            snowflake.execute({sqlText: 'show grants on role "' + obj_rs.getColumnValue(1) + '" ;' });
            snowflake.execute( {sqlText:`
                insert into dbgrants
                select *,CURRENT_TIMESTAMP()
                from table(result_scan(last_query_id()))
                ;`
            });
        }
    }
   // ------------------------------------------------

    function user_grants(){
        var obj_rs = snowflake.execute({sqlText: `
            SELECT NAME FROM DBUSERS
            WHERE DISABLED = FALSE
            `});

        while(obj_rs.next()) {
            snowflake.execute({sqlText: 'show grants to user "' + obj_rs.getColumnValue(1) + '" ;' });
            snowflake.execute( {sqlText:`
                insert into dbgrants
                select *,null,null,null,CURRENT_TIMESTAMP()
                from table(result_scan(last_query_id()))
            ;`
            });

            snowflake.execute({sqlText: 'show grants on user "' + obj_rs.getColumnValue(1) + '" ;' });
            snowflake.execute( {sqlText:`
                insert into dbgrants
                select *,CURRENT_TIMESTAMP()
                from table(result_scan(last_query_id()))
            ;`
            });
        }
    }
  
   // ------------------------------------------------

    var result = "SUCCESS";
    try {
        role_grants();
        user_grants();

    } catch (err)  {
        result =  "FAILED: Code: " + err.code + "\n  State: " + err.state;
        result += "\n  Message: " + err.message;
        result += "\nStack Trace:\n" + err.stackTraceTxt;
    }

    return result;
 $$
;
```

#### Executing Stored Procedures

When we run the show command to get the full depth across the entire snowflake
subscription, you would have to *execute as the SECURITYADMIN*. If you run 
the SHOW command under your ID; it will display only the roles, grants accessible
to the current role.

Also a good tidbit is that when calling the SHOW command inside a stored procedure 
,you have to set **EXECUTE AS CALLER** as highlighted in this how to
[How-to-USE-SHOW-COMMANDS-in-Stored-Procedures](https://snowflakecommunity.force.com/s/article/How-to-USE-SHOW-COMMANDS-in-Stored-Procedures).
  
```sql
USE ROLE SECURITYADMIN;

call SNAPSHOT_USERS();
call SNAPSHOT_ROLES();
call SNAPSHOT_GRANTS();
```

Once the execution is complete the tables would be populated accordingly.
The 'SNAPSHOT_GRANTS' will take a little bit longer time to execute.   

Due to security restrictions I am not able to display the tables and 
demonstrate with screenshot. Hence these are exercises left to you to explore.  
