CREATE OR REPLACE FUNCTION public.Selector(
_FilterSchema name    DEFAULT NULL,
_FilterTable  name    DEFAULT NULL,
_FilterColumn name    DEFAULT NULL
)
RETURNS json
STABLE
LANGUAGE plpgsql
AS $FUNC$
DECLARE
_SchemaNames name[];
_TableNames  name[];
_ColumnNames name[];
BEGIN
SELECT
    array_agg(DISTINCT pg_namespace.nspname ORDER BY pg_namespace.nspname),
    array_agg(DISTINCT pg_class.relname     ORDER BY pg_class.relname    ),
    array_agg(DISTINCT pg_attribute.attname ORDER BY pg_attribute.attname)
INTO STRICT
    _SchemaNames,
    _TableNames,
    _ColumnNames
FROM pg_attribute
INNER JOIN pg_class     ON pg_class.oid     = pg_attribute.attrelid
INNER JOIN pg_namespace ON pg_namespace.oid = pg_class.relnamespace
WHERE pg_class.relkind = 'r'
AND pg_attribute.attnum > 0
AND pg_relation_size(pg_class.oid) > 0
AND pg_namespace.nspname !~ '^(pg_(toast.*|temp.*|catalog)|information_schema)$'
AND NOT pg_is_other_temp_schema(pg_namespace.oid)
AND (_FilterSchema IS NULL OR pg_namespace.nspname = _FilterSchema)
AND (_FilterTable  IS NULL OR pg_class.relname     = _FilterTable)
AND (_FilterColumn IS NULL OR pg_attribute.attname = _FilterColumn);
RETURN json(
    'schemas' *> _SchemaNames,
    'tables'  *> _TableNames,
    'columns' *> _ColumnNames
);
END;
$FUNC$;

CREATE OR REPLACE FUNCTION public.Selector(
_Schema    name,
_Table     name,
_Column    name    DEFAULT NULL,
_Value     text    DEFAULT NULL,
_Limit     bigint  DEFAULT 10,
_Offset    bigint  DEFAULT 0,
_NULLValue boolean DEFAULT FALSE
)
RETURNS json
STABLE
LANGUAGE plpgsql
AS $FUNC$
DECLARE
_ChildColumns  json;
_Children      json;
_ColumnName    name;
_Columns       name[];
_ColumnValue   text;
_Exists        boolean;
_Family        json;
_ParentColumns json;
_Parents       json;
_RelatedColumn name;
_RelatedData   json;
_RelatedSchema name;
_RelatedTable  name;
_RelationType  text;
_RecordSet     json;
_Row           record;
_Rows          json;
_TableOID      oid;
_Values        hstore;
_HStoreKey     text;
_HStoreValue   text;
BEGIN
_RecordSet := json();
SELECT   pg_class.oid
INTO STRICT _TableOID
FROM pg_class
INNER JOIN pg_namespace ON pg_namespace.oid = pg_class.relnamespace
WHERE pg_namespace.nspname = _Schema
AND pg_class.relname       = _Table
AND pg_class.relkind       = 'r'
AND pg_namespace.nspname  !~ '^(pg_(toast.*|temp.*|catalog)|information_schema)$'
AND NOT pg_is_other_temp_schema(pg_namespace.oid)
AND (_Column IS NULL OR EXISTS (
    SELECT 1 FROM pg_attribute
    WHERE attrelid = pg_class.oid
    AND   attnum   > 0
    AND   attname  = _Column
));

SELECT array_agg(attname ORDER BY attnum)
INTO _Columns
FROM pg_attribute
WHERE attrelid = _TableOID
AND   attnum   > 0;
_Rows := json_array();
FOR _Row IN
EXECUTE format(
    'SELECT * FROM %I.%I
    %s
    %s
    %s',
    _Schema, _Table,
    CASE
    WHEN _Column IS NOT NULL AND _Value IS NOT NULL THEN
        format('WHERE  %I.%I.%I = %L', _Schema, _Table, _Column, _Value)
    WHEN _Column IS NOT NULL AND _NULLValue IS TRUE THEN
        format('WHERE  %I.%I.%I IS NULL', _Schema, _Table, _Column)
    END,
    CASE WHEN _Limit  IS NOT NULL THEN 'LIMIT ' || _Limit END,
    CASE WHEN _Offset IS NOT NULL THEN 'OFFSET '|| _Offset END
)
LOOP
    _Values   := hstore(_Row);
    _Parents  := json();
    _Children := json();

    FOR
        _ColumnName,
        _RelationType,
        _RelatedSchema,
        _RelatedTable,
        _RelatedColumn
    IN
    WITH FKs AS (
        SELECT
        ParentTable.oid      AS ParentOID,
        ParentSchema.nspname AS ParentSchema,
        ParentTable.relname  AS ParentTable,
        ParentColumn.attname AS ParentColumn,
        ChildTable.oid       AS ChildOID,
        ChildSchema.nspname  AS ChildSchema,
        ChildTable.relname   AS ChildTable,
        ChildColumn.attname  AS ChildColumn
        FROM pg_constraint      AS ForeignKey
        INNER JOIN pg_class     AS ParentTable   ON ParentTable.oid       = ForeignKey.confrelid
        INNER JOIN pg_attribute AS ParentColumn  ON ParentColumn.attrelid = ForeignKey.confrelid
                                                AND ParentColumn.attnum   = ForeignKey.confkey[1]
        INNER JOIN pg_class     AS ChildTable    ON ChildTable.oid        = ForeignKey.conrelid
        INNER JOIN pg_attribute AS ChildColumn   ON ChildColumn.attrelid  = ForeignKey.conrelid
                                                AND ChildColumn.attnum    = ForeignKey.conkey[1]
        INNER JOIN pg_namespace AS ParentSchema  ON ParentSchema.oid      = ParentTable.relnamespace
        INNER JOIN pg_namespace AS ChildSchema   ON ChildSchema.oid       = ChildTable.relnamespace
        WHERE _TableOID IN (ParentTable.oid,ChildTable.oid)
        AND ForeignKey.contype                = 'f'
        AND array_length(ForeignKey.conkey,1) = 1 -- only single-column FKs are supported
    )
    SELECT ParentColumn, 'CHILD',  ChildSchema,  ChildTable,  ChildColumn  FROM FKs WHERE ParentOID = _TableOID
    UNION ALL
    SELECT ChildColumn,  'PARENT', ParentSchema, ParentTable, ParentColumn FROM FKs WHERE ChildOID  = _TableOID
    ORDER BY 1,2,3,4,5
    LOOP
        SELECT Value INTO STRICT _ColumnValue FROM (SELECT * FROM each(hstore(_Values))) AS X WHERE Key = _ColumnName;

        IF _ColumnValue IS NULL THEN
            CONTINUE;
        END IF;
        EXECUTE format('
            SELECT EXISTS (
                SELECT 1
                FROM   %I.%I
                WHERE  %I.%I.%I = %L
            );
        ',
            _RelatedSchema, _RelatedTable,
            _RelatedSchema, _RelatedTable, _RelatedColumn, _ColumnValue
        ) INTO STRICT _Exists;
        IF NOT _Exists THEN
            CONTINUE;
        END IF;
        _RelatedData := json(
            'schema' *> _RelatedSchema,
            'table'  *> _RelatedTable,
            'column' *> _RelatedColumn,
            'value'  *> _ColumnValue,
            'label'  *> Get_Unique_Name_For_ID(_RelatedSchema,_RelatedTable,_RelatedColumn,_ColumnValue)
        );
        IF _RelationType = 'PARENT' THEN
            IF _Parents ? _ColumnName THEN
                _Parents := json_set(
                    _Parents,
                    json(
                        _ColumnName *> json_push(
                            json_extract_path(
                                _Parents,
                                ARRAY[_ColumnName]
                            )::json,
                            _RelatedData
                        )
                    )
                );
            ELSE
                _Parents := json_set(_Parents, json(_ColumnName *> json_array(_RelatedData)));
            END IF;
        ELSIF _RelationType = 'CHILD'  THEN
            IF _Children ? _ColumnName THEN
                _Children := json_set(
                    _Children,
                    json(
                        _ColumnName *> json_push(
                            json_extract_path(
                                _Children,
                                ARRAY[_ColumnName]
                            )::json,
                            _RelatedData
                        )
                    )
                );
            ELSE
                _Children := json_set(_Children, json(_ColumnName *> json_array(_RelatedData)));
            END IF;
        END IF;
    END LOOP;
    _Family := json();
    FOR _HStoreKey, _HStoreValue IN
    SELECT Key, Value FROM each(hstore(_Values))
    LOOP
        _Family := json_set(_Family, json(_HStoreKey *> _HStoreValue));
    END LOOP;
    _Family := json('values' *> _Family);
    IF _Parents::text  <> '{}' THEN _Family := json_set(_Family, json('parents'  *> _Parents));  END IF;
    IF _Children::text <> '{}' THEN _Family := json_set(_Family, json('children' *> _Children)); END IF;
    _Rows := json_push(_Rows, _Family);
END LOOP;
_RecordSet := json_set(_RecordSet, json(
    _TableOID::regclass::text *> json(
        'columns' *> _Columns,
        'rows'    *> _Rows
    )
));
RETURN json('recordset' *> _RecordSet);
END;
$FUNC$;
