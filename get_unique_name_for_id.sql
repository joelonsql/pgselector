CREATE OR REPLACE FUNCTION public.Get_Unique_Name_For_ID(
_Schema name,
_Table  name,
_Column name,
_Value  text
)
RETURNS text
LANGUAGE plpgsql
STABLE
AS $FUNC$
DECLARE
_UniqueNameColumn text;
_UniqueNameValue text;
BEGIN

SELECT UniqueNameColumn.attname
INTO  _UniqueNameColumn
FROM pg_class
INNER JOIN pg_namespace                          ON pg_namespace.oid                 = pg_class.relnamespace
INNER JOIN pg_attribute  AS UniqueIDColumn       ON UniqueIDColumn.attrelid          = pg_class.oid
INNER JOIN pg_constraint AS UniqueIDConstraint   ON UniqueIDConstraint.conrelid      = UniqueIDColumn.attrelid
                                                AND UniqueIDConstraint.conkey[1]     = UniqueIDColumn.attnum
                                                AND UniqueIDConstraint.contype      IN ('p','u')
INNER JOIN pg_attribute  AS UniqueNameColumn     ON UniqueNameColumn.attrelid        = pg_class.oid
INNER JOIN pg_constraint AS UniqueNameConstraint ON UniqueNameConstraint.conrelid    = UniqueNameColumn.attrelid
                                                AND UniqueNameConstraint.conkey[1]   = UniqueNameColumn.attnum
                                                AND UniqueNameConstraint.contype    IN ('p','u')
INNER JOIN pg_type                               ON pg_type.oid                      = UniqueNameColumn.atttypid
WHERE pg_namespace.nspname                      = _Schema
AND pg_class.relname                            = _Table
AND UniqueIDColumn.attname                      = _Column
AND UniqueNameColumn.attnotnull                 IS TRUE
AND pg_type.typcategory                         = 'S'
AND array_length(UniqueIDConstraint.conkey,1)   = 1
AND array_length(UniqueNameConstraint.conkey,1) = 1;
IF FOUND THEN
    EXECUTE format('
            SELECT %I
            FROM   %I.%I
            WHERE  %I.%I.%I = %L;
    ',
        _UniqueNameColumn,
        _Schema, _Table,
        _Schema, _Table, _Column, _Value
    ) INTO STRICT _UniqueNameValue;
END IF;
RETURN _UniqueNameValue;
END;
$FUNC$;
