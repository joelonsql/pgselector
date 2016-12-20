CREATE OR REPLACE FUNCTION public.Selector(
_FilterSchema name    DEFAULT NULL,
_FilterTable  name    DEFAULT NULL,
_FilterColumn name    DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
AS $FUNC$
DECLARE
_SchemaNames jsonb;
_TableNames  jsonb;
_ColumnNames jsonb;
BEGIN
SELECT
    to_jsonb(array_agg(DISTINCT pg_namespace.nspname ORDER BY pg_namespace.nspname)),
    to_jsonb(array_agg(DISTINCT pg_class.relname     ORDER BY pg_class.relname    )),
    to_jsonb(array_agg(DISTINCT pg_attribute.attname ORDER BY pg_attribute.attname))
INTO STRICT
    _SchemaNames,
    _TableNames,
    _ColumnNames
FROM pg_attribute
INNER JOIN pg_class     ON pg_class.oid     = pg_attribute.attrelid
INNER JOIN pg_namespace ON pg_namespace.oid = pg_class.relnamespace
WHERE pg_class.relkind = 'r'
AND pg_attribute.attnum > 0
AND pg_attribute.attisdropped IS FALSE
AND pg_relation_size(pg_class.oid) > 0
AND pg_namespace.nspname !~ '^(pg_(toast.*|temp.*|catalog)|information_schema)$'
AND NOT pg_is_other_temp_schema(pg_namespace.oid)
AND (_FilterSchema IS NULL OR pg_namespace.nspname = _FilterSchema)
AND (_FilterTable  IS NULL OR pg_class.relname     = _FilterTable)
AND (_FilterColumn IS NULL OR pg_attribute.attname = _FilterColumn);
RETURN jsonb_build_object(
    'schemas', _SchemaNames,
    'tables',  _TableNames,
    'columns', _ColumnNames
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
RETURNS jsonb
LANGUAGE plpgsql
AS $FUNC$
DECLARE
_ChildColumns  jsonb;
_Children      jsonb;
_ColumnName    name;
_Columns       jsonb;
_ColumnValue   text;
_Exists        boolean;
_Family        jsonb;
_ParentColumns jsonb;
_Parents       jsonb;
_RelatedColumn name;
_RelatedData   jsonb;
_RelatedSchema name;
_RelatedTable  name;
_RelationType  text;
_RecordSet     jsonb;
_Row           record;
_Rows          jsonb;
_TableOID      oid;
_Values        jsonb;
BEGIN
_RecordSet := jsonb_build_object();
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
    WHERE attrelid     = pg_class.oid
    AND   attnum       > 0
    AND   attisdropped IS FALSE
    AND   attname      = _Column
));

SELECT to_jsonb(array_agg(attname ORDER BY attnum))
INTO _Columns
FROM pg_attribute
WHERE attrelid     = _TableOID
AND   attnum       > 0
AND   attisdropped IS FALSE;
_Rows := jsonb_build_array();
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
    _Values   := row_to_json(_Row)::jsonb;
    _Parents  := jsonb_build_object();
    _Children := jsonb_build_object();

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
        _ColumnValue := jsonb_extract_path_text(_Values, _ColumnName);
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
        _RelatedData := jsonb_object(ARRAY[
            ['schema', _RelatedSchema],
            ['table',  _RelatedTable],
            ['column', _RelatedColumn],
            ['value',  _ColumnValue],
            ['label', Get_Unique_Name_For_ID(_RelatedSchema,_RelatedTable,_RelatedColumn,_ColumnValue)]
        ]);
        IF _RelationType = 'PARENT' THEN
            IF _Parents ? _ColumnName THEN
                _Parents := jsonb_insert(_Parents, ARRAY[_ColumnName, '0'], _RelatedData);
            ELSE
                _Parents := _Parents || jsonb_build_object(_ColumnName, jsonb_build_array(_RelatedData));
            END IF;
        ELSIF _RelationType = 'CHILD'  THEN
            IF _Children ? _ColumnName THEN
                _Children := jsonb_insert(_Children, ARRAY[_ColumnName, '0'], _RelatedData);
            ELSE
                _Children := _Children || jsonb_build_object(_ColumnName, jsonb_build_array(_RelatedData));
            END IF;
        END IF;
    END LOOP;
    _Family := jsonb_build_object('values', _Values);
    IF _Parents  <> '{}'::jsonb THEN _Family := _Family || jsonb_build_object('parents',  _Parents);  END IF;
    IF _Children <> '{}'::jsonb THEN _Family := _Family || jsonb_build_object('children', _Children); END IF;
    _Rows := _Rows || _Family;
END LOOP;
_RecordSet := _RecordSet || jsonb_build_object(
    _TableOID::regclass, jsonb_build_object(
        'columns', _Columns,
        'rows',    _Rows
    )
);
RETURN jsonb_build_object('recordset', _RecordSet);
END;
$FUNC$;
