# pgundolog

pgundolog is a system for rolling back changes to a PostgreSQL database without using transactions.

The primary use case is integration testing an application with database usage. This requires a clean database at the
beginning of each test.

The simplest approach is to create a new database for each test. This can be done by using a database set up for testing
as a template database and cloning the database with something like `create database foo_test_123 template
foo_test_original`. However, creating and dropping a database costs on the order of 500ms. While this may be acceptable
for long tests, it is unacceptable when there are many short tests.

The fastest approach is to use a database transaction around the entire test and roll back any changes. Unfortunately,
it is often inconvenient or impossible to structure the application and test to use a single transaction that can be
rolled back. In addition, when running tests in parallel it is possible for transactional tests to block one another.

pgundolog uses triggers to capture every change made to the database into an undo log. With that it can revert the
database to its original state.

Install by running `pgundolog.sql`.

```sql
psql -f pgundolog.sql
```

Activate the undo log for a table with `pgundolog.create_trigger_for_table(schema_name text, table_name text)`.

```sql
select pgundolog.create_trigger_for_table('public', 'users');
```

Or activate an entire schema with `pgundolog.create_trigger_for_all_tables_in_schema(schema_name text)`.

```sql
select pgundolog.create_trigger_for_all_tables_in_schema('public');
```

To roll back changes run `pgundolog.undo()`.

```sql
select pgundolog.undo()
```

To uninstall drop the `pgundolog` schema.

```sql
drop schema pgundolog cascade;
```
