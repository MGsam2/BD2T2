--EXPERIMENTO 1 - OLTP POINT LOOKUP -accceso por PK--------------------
--medir y comparar el costo de buscar un solo registro por clave primaria en PostgreSQL(heap storage)
--y tambien en MySQL usando InnoDB(clustered index)

--EN POSTGRESQL
--crear base de datos o la que tenga a disposicion
create database lab_storagealter;

\c lab_storagealter; --CONECTAR CON LA BD


--crear tabla
drop table if exists clientes_pg;

create table clientes_pg(
	id bigserial primary key ,
	nombre text
);
--bigserial crea automaticamente secuencia e indice primario

--insertar 10M de registros
insert into clientes_pg(nombre)
select md5(random()::text)
from generate_series(1, 10000000);
--los datos se insertan en el heap

--Ejecutar EXPLAIN ANALYZE
explain (analyze, buffers) select *
from clientes_pg
where id = 5000000;

--se observara el mensaje "Index Scan using clientes_pg_pkey on clientes_pg"
-- que pasa? el index scan busca el indice btree - obtiene el TID - ve al heap y lee la fila son accesos logicos uno al indice y otro al heap

--EN MYSQL CON INNODB//////////////////////////
--opcional crear DB

--crear tabla
drop table if exists clientes_mysql;

create table clientes_mysql (
	id bigint auto_increment primary key,
	nombre varchar(100)
) Engine=InnoDB;
--la tabla es el indice primario y los datos estan fisicamente ordenados por PK

--debemos de ejecutar para extender el limite de recursividad que por defecto es 1000
set session cte_max_recursion_depth = 10000000;
--Insertar 10M datos usando mysql 8
INSERT INTO clientes_mysql(nombre)
WITH RECURSIVE seq AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM seq WHERE n < 10000000
)
SELECT MD5(RAND())
FROM seq;

--ejecutar explain analyze
explain analyze
select * from clientes_mysql where id = 5000000;
-- se observa rows fetched before execution

--¿Por qué el acceso por PK en InnoDB es más eficiente cuando no hay caché?
--porque en innoBD la tabla esta fisicamente organizada por la clave primaria,
--el indice primario contiene directamente los datos,
--solo se necesita una lectura de pagina. entonces el diseño clusterizado de Innodb 
--reduce el I/O en accesos puntuales haciendolo mas eficiente en cargas OLTP

---------------------------------------------------------------------------------------------
--EXPERIMENTO 2 - IMPACTO DEL TIPO DE PK EN INNODB-------------------------------------------
--EN MYSQL CON INNODB
--para comparar bigint auto_increment (pk secuencial)
--char(36) UUID (pk aleatoria)

--crear tablas

drop table if exists t_bigint;
drop table if exists t_uuid;

create table t_bigint (
	id bigint auto_increment primary key,
	data text
)engine = InnoDB;

create table t_uuid(
	id char(36) primary key,
	data text
)engine=InnoDB;

--Medir tiempo de insercion
--insert bigint
SET SESSION cte_max_recursion_depth = 5000000;

INSERT INTO t_bigint (data)
WITH RECURSIVE seq AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM seq WHERE n < 5000000
)
SELECT MD5(RAND())
FROM seq;

--insert uuid
INSERT INTO t_uuid
WITH RECURSIVE seq AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM seq WHERE n < 5000000
)
SELECT UUID(), MD5(RAND())
FROM seq;

--tamaño en disco
select table_name, 
	round(data_length/1024/1024,2) as data_mb,
	round(index_length/1024/1024,2) as index_mb
	from information_schema.tables
	where table_schema = DATABASE();

--fragmentación
show table status like 't_bigint';
show table status like 't_uuid';
--se observara data_lenght, index_lenght y data_free que es fragmentacion
--se observara bigint_autoincrement, insercion mas rapida, menos fragmentacion, indice compacto
--en uuid, la insercion mas lenta, mas fragmentacion, indice mas grande, page splits.

------------------------------------------------------------------------------------------------
--EXPERIMENTO 3 - VACUUM y dead tuples en PostgreSQL----------------------------------------------
--crear tabla
drop table if exists productos_pg;

create table productos_pg(
	id SERIAL primary key ,
	precio INT
);
	
--insertar 10M filas
insert into productos_pg (precio) select 100 from generate_series(1,10000000);

--Medir el tamaño inicial
select pg_size_pretty(pg_total_relation_size('productos_pg'));

--Ejecutar 1M de updates
update productos_pg set precio = precio + 1 where id <= 1000000;

--Ver dead tuples
select n_live_tup, n_dead_tup from pg_stat_user_tables where relname='productos_pg';

--Ejecutar VACUUM
vacuum productos_pg;
--revision
select n_live_tup, n_dead_tup from pg_stat_user_tables where relname='productos_pg';

-------------------------------------------------------------------------------------
--EXPERIMENTO 4 - consulta analitica-------------------------------------------------
-- motor postgresql

drop table if exists ventas;

CREATE TABLE ventas (
    id SERIAL PRIMARY KEY,
    region TEXT,
    total NUMERIC,
    c1 TEXT, c2 TEXT, c3 TEXT, c4 TEXT, c5 TEXT,
    c6 TEXT, c7 TEXT, c8 TEXT, c9 TEXT, c10 TEXT,
    c11 TEXT, c12 TEXT
);

--insertar 10M 
INSERT INTO ventas (region, total, c1,c2,c3,c4,c5,c6,c7,c8,c9,c10,c11,c12)
SELECT 
	CASE 
	    WHEN r < 0.25 THEN 'Norte'
	    WHEN r < 0.50 THEN 'Sur'
	    WHEN r < 0.75 THEN 'Este'
	    ELSE 'Oeste'
	END,
    random()*1000,
    md5(random()::text), md5(random()::text),
    md5(random()::text), md5(random()::text),
    md5(random()::text), md5(random()::text),
    md5(random()::text), md5(random()::text),
    md5(random()::text), md5(random()::text),
    md5(random()::text), md5(random()::text)
FROM (
    SELECT random() as r, random() as r2
    FROM generate_series(1,10000000)
) sub;

--	QUERY A
explain (analyze, buffers) select * from ventas where region = 'Norte';

-- QUERY B
explain (analyze, buffers) select sum(total), count(*) from ventas where region = 'Norte';

--query b solo usa 2 columnas pero lee todas las paginas, similar I/O que Query A.
-- demostrando limitacion de row-store

--------------------------------------------------------------------------------------------
--EXPERIMENTO 5 - Convering Index-----------------------------------------------------------
create index idx_ventas_covering on ventas(region) include (total);

--ahora se repite el queryB
-- QUERY B
explain (analyze, buffers) select sum(total), count(*) from ventas where region = 'Norte';
--mostrando Index Only Scan. y menos buffers leidos.












