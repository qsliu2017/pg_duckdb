create table t1 (a int, b int) using ducklake;
insert into t1 values (1, 2);
select * from t1;
drop table t1;
