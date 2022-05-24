create schema pgundolog;

create table pgundolog.changes (
	id bigint primary key generated by default as identity,
	tg_table_schema text not null,
	tg_table_name text not null,
	tg_op text not null,
	old jsonb,
	new jsonb
);

create function pgundolog.record_changes() returns trigger
language plpgsql as $$
begin
	insert into pgundolog.changes (tg_table_schema, tg_table_name, tg_op, old, new)
	values (tg_table_schema, tg_table_name, tg_op, to_jsonb(old), to_jsonb(new));
	return null;
end;
$$;


create function pgundolog.create_trigger_for_table(schema_name text, table_name text) returns void
language plpgsql as $$
begin
	execute format(
		'create trigger process_undolog after insert or update or delete on %I.%I for each row execute function pgundolog.record_changes();',
		$1, $2
	);
end
$$;

create function pgundolog.create_trigger_for_all_tables_in_schema(schema_name text) returns void
language plpgsql as $$
declare
  _table_name text;
begin
	for _table_name in select tablename from pg_catalog.pg_tables where schemaname = $1
	loop
		perform pgundolog.create_trigger_for_table($1, _table_name);
	end loop;
end
$$;

create function pgundolog.undo() returns void
language plpgsql as $$
declare
	c pgundolog.changes;
	column_names text;
	key_column_names text;
begin
	for c in select * from pgundolog.changes order by id desc
	loop
		select string_agg(a.attname, ', '), string_agg(a.attname, ', ') filter (where i.indisprimary)
		from pg_attribute a
			left join pg_index i on a.attrelid = i.indrelid and a.attnum = any(i.indkey) and i.indisprimary
		where a.attrelid = format('%I.%I', c.tg_table_schema, c.tg_table_name)::regclass
			and a.attnum > 0
			and not a.attisdropped
		into strict column_names, key_column_names;

		-- Use entire row if no primary key exists.
		if key_column_names is null then
			key_column_names = column_names;
		end if;

		if c.tg_op = 'DELETE' then
			execute format(
				'insert into %1$I.%2$I select * from jsonb_populate_record(null::%1$I.%2$I, $1)',
				c.tg_table_schema, c.tg_table_name
			) using c.old;
		elsif c.tg_op = 'UPDATE' then
			execute format(
				'update %1$I.%2$I t ' ||
				'set (%3$s) = (select * from jsonb_populate_record(null::%1$I.%2$I, $1)) ' ||
				'where (%4$s) = (select (%4$s) from jsonb_populate_record(null::%1$I.%2$I, $2))',
				c.tg_table_schema, c.tg_table_name, column_names, key_column_names
			) using c.old, c.new;
		elsif c.tg_op = 'INSERT' then
			execute format(
				'delete from %1$I.%2$I t ' ||
				'where (%4$s) = (select (%4$s) from jsonb_populate_record(null::%1$I.%2$I, $2))',
				c.tg_table_schema, c.tg_table_name
			) using c.new;
		else
			raise 'unknown tg_op %', c.tg_op;
		end if;
	end loop;

	delete from pgundolog.changes;
end
$$;
