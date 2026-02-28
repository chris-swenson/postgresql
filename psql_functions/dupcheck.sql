-- Check for duplicates
-- Usage: select dupcheck('table_name', 'id, columns, by, comma', '[additional WHERE criteria]', test:='Y' / 'N')

drop function if exists dupcheck;

CREATE FUNCTION dupcheck(
    source_table TEXT,
    id_columns TEXT, -- Specify the columns that are supposed to identify unique rows
    criteria TEXT DEFAULT '', -- Filter criteria: optional
	test TEXT DEFAULT 'N' -- Use Y to test the function and not execute the dynamic query
)
RETURNS INT AS $$

DECLARE
    counter INT;
    query TEXT;
	
BEGIN

	-- Extend WHERE statement below, which starts with WHERE 1=1
	criteria := CASE WHEN criteria <> '' THEN ' AND ' || criteria ELSE '' END;

	-- Build the query
    query := format(
		'SELECT sum(duplicates)
		FROM (
			SELECT count(*) as duplicates
			FROM %s -- source_table
			WHERE 1=1 %s -- criteria
			GROUP BY %s -- id_columns
			HAVING COUNT(*) > 1
		) a',
        source_table, criteria, id_columns
    );

    -- Execute the query if not in test mode
	-- In test mode, NULL is returned for the number of duplicates, since the query isn't run
	-- If duplicates are present, output different messages.
	-- A war-ning is issued if duplicates are present
    IF test = 'Y' THEN
		RAISE NOTICE 'criteria: %', criteria;
        RAISE NOTICE 'Executed Query:';
		RAISE NOTICE '    %', query;
		RETURN null;
	ELSE
		EXECUTE query INTO counter;
		IF counter > 0 THEN
			RAISE WARNING '% duplicates found in %!', counter, source_table;
			RETURN counter;
		ELSE
			RAISE NOTICE 'No duplicates found in %.', source_table;
			RETURN 0;
		END IF;
    END IF;
	
END;
$$ LANGUAGE plpgsql;

-- Examples

-- Try on a table without duplicates
-- select dupcheck('information_schema.tables', 'table_name')

-- Make a table with duplicates
-- drop table if exists tables_copy;
-- create temporary table tables_copy as select table_schema, table_name, 1 as table_id from information_schema.tables;
-- insert into tables_copy select table_schema, table_name, 2 from information_schema.tables where table_name like 'pg_%';
-- insert into tables_copy select table_schema, table_name, 3 from information_schema.tables where table_name like 'sch%';

-- Try on a table with duplicates
-- select dupcheck('tables_copy', 'table_name');

-- Test on a table with duplicates
-- select dupcheck('tables_copy', 'table_name', test:='Y');

-- Try on a table with duplicates, but add a filter that removes them
-- select dupcheck('tables_copy', 'table_name', criteria:='table_id = 1');

-- Try on a table with duplicates, but add a filter that removes most of them
-- select dupcheck('tables_copy', 'table_name', criteria:='table_name NOT like ''pg_%''');

-- Test on a table with duplicates, but add a filter that removes most of them
-- select dupcheck('tables_copy', 'table_name', criteria:='table_name NOT like ''pg_%''', test:='Y');
