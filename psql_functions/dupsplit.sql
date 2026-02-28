-- Split duplicates (or optionally, non-duplicates) from a table into a temporary table
-- Common Usage: select dupsplit('table_name', 'id, columns, by, comman', 'output_table_name', '[additional WHERE criteria]')
-- Note: Use 'schema.table_name' for permanent tables in a specific schema
-- Set duplicates := 'N' to split non-duplicates out instead
-- Set sort_output := 'N' for large datasets, since sorting may be costly
-- Set permanent := 'Y' to output to a permanent table - specify a schema and dot in output_table

drop function if exists dupsplit;

CREATE FUNCTION dupsplit(
    source_table TEXT, 
    id_columns TEXT, -- Specify the columns that are supposed to identify unique rows
	output_table TEXT, -- Specify temporary table name that the results should be returned to
	criteria TEXT DEFAULT '', -- Filter criteria: optional
    duplicates TEXT DEFAULT 'Y', -- Use Y for duplicates, N for singles (all rows except duplicates)
	sort_output TEXT DEFAULT 'Y', -- Use Y to sort the output, anything else won't sort it
	permanent TEXT DEFAULT 'N', -- Use Y for permanent output table
	test TEXT DEFAULT 'N' -- Use Y to test the function and not execute the dynamic query
)
RETURNS INT AS $$

DECLARE
    query1 TEXT;
	query2 TEXT;
	query3 TEXT;
	on_clause TEXT;
	counter INT;
	type_criteria TEXT;
	
BEGIN

	-- Handle duplicates argument
	duplicates := upper(substring(duplicates, 1, 1));
	if duplicates = 'Y' then
		type_criteria := 'COUNT(*) > 1';
	elseif duplicates = 'N' then
		type_criteria := 'COUNT(*) = 1';
	else 
		RAISE EXCEPTION 'Invalid value for duplicates argument: %. Use Y for duplicates or N for singles.', duplicates;
	end if;

	-- Handle permanent argument
	permanent := upper(substring(permanent, 1, 1));
	if permanent = 'N' then
		query1 := format(
			'create temporary table %s as select * from %s where 1=0;', 
			output_table, source_table
		);
	elseif permanent = 'Y' then
		query1 := format(
			'create table %s as select * from %s where 1=0;', 
			output_table, source_table
		);
	else
		RAISE EXCEPTION 'Invalid value for permanent argument: %. Use Y for permanent or N for temporary table output.', duplicates;
	end if;

	-- Handle sort_output argument: Just check it
	sort_output := upper(substring(sort_output, 1, 1));
	if sort_output = 'N' then
	elseif sort_output = 'Y' then
	else
		RAISE EXCEPTION 'Invalid value for sort_output argument: %. Use Y to sort or N to not sort.', duplicates;
	end if;

	-- Handle test argument: Just check it
	test := upper(substring(test, 1, 1));
	if test = 'N' then
	elseif test = 'Y' then
	else
		RAISE EXCEPTION 'Invalid value for test argument: %. Use Y to test or N to not test.', duplicates;
	end if;

	-- Handle criteria argument
	-- Extend WHERE statement in dynamic query, that already contains "WHERE 1=1"
	criteria := CASE WHEN criteria <> '' THEN ' AND ' || criteria ELSE '' END;

    -- Construct the ON statements for the INNER JOIN
	-- For each column, create an ON statement
    SELECT string_agg(format('a.%s = b.%s', trim(col), trim(col)), ' AND ') 
    INTO on_clause
    FROM unnest(string_to_array(id_columns, ',')) AS col
	;
	
	-- Build the main query
    query2 := format(
		'INSERT INTO %s -- output_table
		SELECT a.* 
		FROM %s as a -- source_table
		INNER JOIN (
			SELECT %s -- id_columns
			FROM %s -- source_table
			WHERE 1=1 %s -- criteria
			GROUP BY %s -- id_columns
			HAVING %s -- type_criteria
		) as b
		ON %s -- on_clause
		',
        output_table, source_table, id_columns, source_table, criteria, id_columns, type_criteria, on_clause
    );

	query3 := format('drop table %s;', output_table);

    -- Append ORDER BY clause if sort_output is 'Y'
    IF sort_output = 'Y' THEN
        query2 := query2 || format('ORDER BY %s', id_columns);
    END IF;

    -- Execute the query if not in test mode
	-- In test mode, NULL is returned for the number of duplicates, since the query isn't run
	-- If duplicates are present, output different messages.
	-- A war-ning is issued if duplicates are present
    IF test = 'Y' THEN
		RAISE NOTICE 'criteria: %', criteria;
		RAISE NOTICE 'on_clause: %', on_clause;
        RAISE NOTICE 'Executed Query:';
		RAISE NOTICE '    %', query1;
		RAISE NOTICE '    %', query2;
		RETURN null;
	ELSE
		EXECUTE query1;
		EXECUTE query2;
        GET DIAGNOSTICS counter = ROW_COUNT;

		IF counter = 0 THEN
			EXECUTE query3;
			RAISE NOTICE 'No records found.';
			RETURN null;
		ELSE 
			RAISE NOTICE 'Output % rows to %.', counter, output_table;
			RETURN counter;
		END IF;
		
    END IF;
	
END;
$$ LANGUAGE plpgsql;

-- Examples

-- Try on a table without duplicates
-- select dupsplit('information_schema.tables', 'table_name', 'duplicate_tables')
-- select * from duplicate_tables; -- this should fail

-- Make a table with duplicates
-- drop table if exists tables_copy;
-- create temporary table tables_copy as select table_schema, table_name, 1 as table_id from information_schema.tables;
-- insert into tables_copy select table_schema, table_name, 2 from information_schema.tables where table_name like 'pg_%';
-- insert into tables_copy select table_schema, table_name, 3 from information_schema.tables where table_name like 'sch%';

-- Try on a table with duplicates
-- drop table if exists duplicate_tables;
-- select dupsplit('tables_copy', 'table_name', 'duplicate_tables');
-- select * from duplicate_tables;

-- Test on a table with duplicates
-- drop table if exists duplicate_tables;
-- select dupsplit('tables_copy', 'table_name', 'duplicate_tables', test:='Y');

-- Try on a table with duplicates, but add a filter that removes them
-- drop table if exists duplicate_tables;
-- select dupsplit('tables_copy', 'table_name', 'duplicate_tables', criteria:='table_id = 1');
-- select * from duplicate_tables; -- this should fail

-- Try on a table with duplicates, but add a filter that removes most of them
-- drop table if exists duplicate_tables;
-- select dupsplit('tables_copy', 'table_name', 'duplicate_tables', criteria:='table_name NOT like ''pg_%''');
-- select * from duplicate_tables;

-- Test on a table with duplicates, but add a filter that removes most of them
-- drop table if exists duplicate_tables;
-- select dupsplit('tables_copy', 'table_name', 'duplicate_tables', criteria:='table_name NOT like ''pg_%''', test:='Y');

-- Output to a permanent table
-- drop table if exists public.duplicate_tables;
-- select dupsplit('tables_copy', 'table_name', 'public.duplicate_tables', criteria:='table_name NOT like ''pg_%''', permanent:='Y');
-- select * from public.duplicate_tables;
-- drop table public.duplicate_tables;
