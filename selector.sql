CREATE OR REPLACE FUNCTION public.Selector(
_FilterSchema name    DEFAULT NULL,
_FilterTable  name    DEFAULT NULL,
_FilterColumn name    DEFAULT NULL,
_FilterValue  text    DEFAULT NULL,
_Limit        bigint  DEFAULT 100,
_Offset       bigint  DEFAULT 0
)
RETURNS text
LANGUAGE plpgsql
AS $FUNC$
DECLARE
_ChildColumns  jsonb;
_Children      jsonb;
_ColumnName    name;
_ColumnNames   jsonb;
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
_Result        jsonb;
_Row           record;
_Rows          jsonb;
_SchemaName    name;
_SchemaNames   jsonb;
_Table         oid;
_TableName     name;
_TableNames    jsonb;
_Values        jsonb;
BEGIN
_Result := jsonb_build_object();
FOR
    _Table,
    _SchemaName,
    _TableName,
    _SchemaNames,
    _TableNames,
    _ColumnNames
IN
SELECT
    pg_class.oid,
    pg_namespace.nspname,
    pg_class.relname,
    to_jsonb(array_agg(DISTINCT pg_namespace.nspname ORDER BY pg_namespace.nspname)),
    to_jsonb(array_agg(DISTINCT pg_class.relname     ORDER BY pg_class.relname    )),
    to_jsonb(array_agg(DISTINCT pg_attribute.attname ORDER BY pg_attribute.attname))
FROM pg_attribute
INNER JOIN pg_class     ON pg_class.oid     = pg_attribute.attrelid
INNER JOIN pg_namespace ON pg_namespace.oid = pg_class.relnamespace
WHERE pg_class.relkind = 'r'
AND pg_attribute.attnum > 0
AND pg_namespace.nspname !~ '^(pg_(toast.*|temp.*|catalog)|information_schema)$'
AND NOT pg_is_other_temp_schema(pg_namespace.oid)
AND (_FilterSchema IS NULL OR pg_namespace.nspname = _FilterSchema)
AND (_FilterTable  IS NULL OR pg_class.relname     = _FilterTable)
AND (_FilterColumn IS NULL OR EXISTS (
    SELECT 1 FROM pg_attribute
    WHERE attrelid = pg_class.oid
    AND   attnum   > 0
    AND   attname  = _FilterColumn
))
GROUP BY pg_class.oid, pg_namespace.nspname, pg_class.relname
ORDER BY pg_namespace.nspname, pg_class.relname
LOOP
    SELECT to_jsonb(array_agg(attname ORDER BY attnum))
    INTO _Columns
    FROM pg_attribute
    WHERE attrelid = _Table
    AND   attnum   > 0;
    _Rows := jsonb_build_array();
    FOR _Row IN
    EXECUTE format(
        'SELECT * FROM %I.%I
        %s
        %s
        %s',
        _SchemaName, _TableName,
        CASE WHEN _FilterColumn IS NOT NULL THEN
            format('WHERE  %I.%I.%I %s', _SchemaName, _TableName, _FilterColumn,
                CASE WHEN _FilterValue IS NOT NULL THEN
                    format('= %L',_FilterValue)
                ELSE 'IS NULL' END
            )
        END,
        CASE WHEN _Limit  IS NOT NULL THEN 'LIMIT ' || _Limit END,
        CASE WHEN _Offset IS NOT NULL THEN 'OFFSET '|| _Offset END
    )
    LOOP
        _Values   := row_to_json(_Row)::jsonb;
        _Parents  := jsonb_build_object();
        _Children := jsonb_build_object();
        FOR _ColumnName IN
        SELECT jsonb_array_elements_text(_Columns)
        LOOP
            _ColumnValue := jsonb_extract_path_text(_Values, _ColumnName);
            _ParentColumns := jsonb_build_array();
            _ChildColumns  := jsonb_build_array();
            FOR
                _RelationType,
                _RelatedSchema,
                _RelatedTable,
                _RelatedColumn
            IN
            SELECT
                RelationType,
                CASE RelationType WHEN 'PARENT' THEN ParentSchema WHEN 'CHILD' THEN ChildSchema END,
                CASE RelationType WHEN 'PARENT' THEN ParentTable  WHEN 'CHILD' THEN ChildTable  END,
                CASE RelationType WHEN 'PARENT' THEN ParentColumn WHEN 'CHILD' THEN ChildColumn END
            FROM (
                SELECT
                CASE
                WHEN ParentTable.oid      = _Table
                AND  ParentColumn.attname = _ColumnName
                THEN 'CHILD'
                WHEN ChildTable.oid       = _Table
                AND  ChildColumn.attname  = _ColumnName
                THEN 'PARENT'
                END                  AS RelationType,
                ParentSchema.nspname AS ParentSchema,
                ParentTable.relname  AS ParentTable,
                ParentColumn.attname AS ParentColumn,
                ChildSchema.nspname  AS ChildSchema,
                ChildTable.relname   AS ChildTable,
                ChildColumn.attname  AS ChildColumn
                FROM pg_constraint       AS ForeignKey
                INNER JOIN pg_class      AS ParentTable   ON ParentTable.oid       = ForeignKey.confrelid
                INNER JOIN pg_attribute  AS ParentColumn  ON ParentColumn.attrelid = ForeignKey.confrelid
                                                         AND ParentColumn.attnum   = ForeignKey.confkey[1]
                INNER JOIN pg_class      AS ChildTable    ON ChildTable.oid        = ForeignKey.conrelid
                INNER JOIN pg_attribute  AS ChildColumn   ON ChildColumn.attrelid  = ForeignKey.conrelid
                                                         AND ChildColumn.attnum    = ForeignKey.conkey[1]
                INNER JOIN pg_namespace  AS ParentSchema  ON ParentSchema.oid      = ParentTable.relnamespace
                INNER JOIN pg_namespace  AS ChildSchema   ON ChildSchema.oid       = ChildTable.relnamespace
                WHERE ForeignKey.contype = 'f'
                AND (_Table,_ColumnName) IN ((ParentTable.oid,ParentColumn.attname),(ChildTable.oid,ChildColumn.attname))
                AND array_length(ForeignKey.conkey,1) = 1 -- only single-column FKs are supported
            ) AS RelatedTables
            LOOP
                EXECUTE format('
                    SELECT EXISTS (
                        SELECT %I
                        FROM   %I.%I
                        WHERE  %I.%I.%I = %L
                    );
                ',
                    _RelatedColumn,
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
                    ['value',  _ColumnValue]
                ]);
                IF    _RelationType = 'PARENT' THEN _ParentColumns := _ParentColumns || _RelatedData;
                ELSIF _RelationType = 'CHILD'  THEN _ChildColumns  := _ChildColumns  || _RelatedData;
                END IF;
            END LOOP;
            IF jsonb_array_length(_ParentColumns) > 0 THEN _Parents  := _Parents  || jsonb_build_object(_ColumnName, _ParentColumns); END IF;
            IF jsonb_array_length(_ChildColumns)  > 0 THEN _Children := _Children || jsonb_build_object(_ColumnName, _ChildColumns);  END IF;
        END LOOP;
        _Family := jsonb_build_object('values', _Values);
        IF _Parents  <> '{}'::jsonb THEN _Family := _Family || jsonb_build_object('parents',  _Parents);  END IF;
        IF _Children <> '{}'::jsonb THEN _Family := _Family || jsonb_build_object('children', _Children); END IF;
        _Rows := _Rows || _Family;
    END LOOP;
    _Result := _Result || jsonb_build_object(
        _Table::regclass, jsonb_build_object(
            'columns', _Columns,
            'rows',    _Rows
        )
    );
END LOOP;
RETURN jsonb_pretty(jsonb_build_object(
    'schemas', _SchemaNames,
    'tables',  _TableNames,
    'columns', _ColumnNames,
    'result',  _Result
));
END;
$FUNC$;
