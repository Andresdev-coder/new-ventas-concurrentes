-- Ejecuta como administrador en pgAdmin, conectado a la base "postgres".
-- Esta primera instrucción crea el usuario si no existe o corrige su contraseña si ya existe.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'ventas') THEN
        ALTER ROLE ventas WITH LOGIN PASSWORD 'ventas';
    ELSE
        CREATE ROLE ventas LOGIN PASSWORD 'ventas';
    END IF;
END
$$;

-- Ejecuta esta segunda instrucción por separado solo si la base "ventas" aún no existe.
-- CREATE DATABASE no se puede ejecutar dentro de una transacción.
CREATE DATABASE ventas OWNER ventas;
