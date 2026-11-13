# Documentación del Sistema de Ventas e Inventario Concurrente

## 1. ¿Qué es el proyecto?

Es una aplicación web de demostración para registrar ventas y administrar un inventario. Cada venta se procesa en segundo plano por un hilo llamado “cajero”. Si todos los cajeros están ocupados, las nuevas ventas esperan en una cola.

El proyecto sirve para observar concurrencia y sincronización entre tres partes:

- **Frontend:** muestra el inventario, permite registrar ventas y actualiza su estado automáticamente.
- **Backend:** valida las solicitudes, guarda las ventas y coordina el trabajo de los cajeros.
- **Base de datos:** conserva los productos, existencias y el historial de ventas.

## 2. Tecnologías

| Tecnología | Uso |
| --- | --- |
| Java 17 o superior | Lenguaje del backend |
| Spring Boot 3 | Servidor HTTP y configuración de la aplicación |
| Spring JDBC (`JdbcTemplate`) | Consultas y actualizaciones en PostgreSQL |
| PostgreSQL | Inventario y registro persistente de ventas |
| React | Interfaz web |
| Vite | Servidor de desarrollo del frontend |
| Maven | Compilación y ejecución del backend |
| Docker Compose (opcional) | Inicio conjunto de PostgreSQL y backend |

## 3. Organización del código

```text
Ventas-concurrentes/
├── backend/
│   ├── src/main/java/com/ventas/
│   │   ├── VentasApplication.java       # Inicio de Spring Boot
│   │   ├── controller/VentaController.java
│   │   ├── service/VentaService.java
│   │   ├── service/InventarioService.java
│   │   ├── service/Resumen.java
│   │   └── model/                       # Venta, Producto y EstadoVenta
│   ├── src/main/resources/
│   │   ├── application.properties       # Puerto y conexión a PostgreSQL
│   │   ├── schema.sql                   # Tablas e índice
│   │   └── data.sql                     # Productos de ejemplo
│   ├── local-db.sql                     # Preparación de PostgreSQL local
│   └── pom.xml                          # Dependencias Maven
├── frontend/
│   ├── src/App.jsx                      # Interfaz y llamadas HTTP
│   └── package.json
└── docker-compose.yml                   # PostgreSQL y backend opcionales
```

### Responsabilidad de las clases principales

- **`VentasApplication`** inicia Spring Boot.
- **`VentaController`** publica las rutas HTTP, valida los datos básicos y llama a los servicios.
- **`VentaService`** guarda cada venta como pendiente, la envía al pool de cajeros y actualiza sus estados.
- **`InventarioService`** consulta el inventario y descuenta o repone existencias en PostgreSQL.
- **`Producto` y `Venta`** representan los datos que usa el backend y devuelve la API.
- **`EstadoVenta`** define los estados posibles de una venta.
- **`Resumen`** contiene contadores de ventas, actividad de cajeros y la comprobación del inventario.
- **`App.jsx`** solicita los datos al backend, dibuja la interfaz y los refresca cada segundo.

## 4. ¿Cómo se procesa una venta?

1. El cliente envía nombre, identificador del producto y cantidad.
2. El controlador comprueba que el nombre no esté vacío y que la cantidad esté entre 1 y 100.
3. `VentaService` verifica que el producto exista y guarda la venta en PostgreSQL con estado `PENDIENTE`.
4. La tarea se entrega al pool fijo de cajeros. El pool tiene cuatro hilos por defecto; se puede cambiar con `CAJEROS`.
5. Un cajero cambia la venta a `EN_PROCESO`, espera entre 0,8 y 3 segundos para simular atención y trata de descontar el inventario.
6. La venta termina como `COMPLETADA` si pudo descontar la cantidad, o como `RECHAZADA` si no había suficiente stock.
7. El backend guarda el estado final y el nombre del hilo que atendió la venta.

La solicitud de venta responde `202 Accepted`: significa que el backend aceptó y puso la tarea en cola. La venta puede seguir pendiente o en proceso; su resultado se consulta después en la lista de ventas.

## 5. ¿Cómo se evita vender más unidades de las disponibles?

El descuento del inventario se hace con una sola sentencia condicional:

```sql
UPDATE productos
SET stock = stock - ?
WHERE id = ? AND stock >= ?;
```

PostgreSQL serializa las actualizaciones que compiten por la misma fila. Si dos cajeros intentan vender las últimas unidades, solo se aplica la actualización que todavía cumple la condición `stock >= cantidad`. Si no se actualiza ninguna fila, la venta se rechaza por falta de stock.

Las consultas usan parámetros de `JdbcTemplate`; los valores enviados por el cliente no se pegan directamente dentro del SQL. El inventario y las ventas se guardan en la base y persisten cuando el backend se reinicia.

## 6. Estados de una venta

| Estado | Significado |
| --- | --- |
| `PENDIENTE` | La tarea espera en la cola de cajeros. |
| `EN_PROCESO` | Un cajero la está atendiendo. |
| `COMPLETADA` | Se descontó el inventario y la venta fue exitosa. |
| `RECHAZADA` | No había inventario suficiente o se interrumpió el trabajo. |

## 7. Base de datos

### Tabla `productos`

Guarda el nombre del producto, el stock inicial y el stock actual. Las restricciones `CHECK` evitan cantidades negativas.

### Tabla `ventas`

Guarda el cliente, el producto vendido, la cantidad, la hora en milisegundos, el estado, el cajero y el mensaje del resultado. Cada venta tiene un ID autogenerado.

Al iniciar, Spring ejecuta `schema.sql` y `data.sql`. El segundo script agrega Laptop, Mouse, Teclado y Monitor solo si todavía no existen. No repone el stock al reiniciar el backend.

### Verificación del resumen

Cuando ya no hay ventas pendientes ni en proceso, `/api/resumen` compara:

```text
unidades descontadas del inventario
contra
suma de cantidades de ventas completadas
```

Si coinciden, `consistente` será `true`. Mientras todavía hay trabajo, el campo será `null`, porque los datos pueden estar cambiando.

## 8. Ejecutar sin Docker

Se requiere Java 17 o superior, Maven 3.9 o superior, PostgreSQL y Node.js 18 o superior.

### Preparar PostgreSQL (una sola vez)

1. Inicia el servicio de PostgreSQL.
2. En pgAdmin, conéctate a la base `postgres` como administrador y abre **Query Tool**.
3. Abre `backend/local-db.sql`.
4. Ejecuta primero el bloque `DO`. Crea el usuario `ventas`, o si ya existe le asigna la contraseña local `ventas`.
5. Ejecuta `CREATE DATABASE ventas OWNER ventas;` por separado si la base `ventas` todavía no existe. No vuelvas a ejecutar esa línea si ya creaste la base.

La configuración predeterminada del backend usa:

| Parámetro | Valor local |
| --- | --- |
| Host y puerto | `localhost:5432` |
| Base de datos | `ventas` |
| Usuario | `ventas` |
| Contraseña | `ventas` |

Estos valores son para desarrollo local. Si usas otros, configúralos en las variables `SPRING_DATASOURCE_URL`, `SPRING_DATASOURCE_USERNAME` y `SPRING_DATASOURCE_PASSWORD`.

### Iniciar el backend

Desde una terminal en la carpeta `backend`:

```powershell
mvn spring-boot:run
```

Si el inicio termina correctamente, el backend queda disponible en `http://localhost:8080`. Mantén abierta esta terminal.

### Iniciar el frontend

Abre otra terminal desde la carpeta `frontend`:

```powershell
npm install
npm run dev
```

Abre `http://localhost:5173`. En desarrollo, el frontend se conecta por defecto al backend en `http://localhost:8080`.

Para detener cada proceso, usa `Ctrl+C` en su terminal.

## 9. Ejecutar con Docker (opcional)

Desde la carpeta raíz del proyecto, con Docker Desktop iniciado:

```powershell
docker compose up --build
```

Esto inicia PostgreSQL y el backend. Ejecuta el frontend por separado con `npm install` y `npm run dev` desde `frontend`. Para detener los contenedores:

```powershell
docker compose down
```

Para borrar también la base persistida en el volumen local:

```powershell
docker compose down -v
```

Ese último comando elimina los datos de la base de Docker.

## 10. API HTTP

Todas las rutas usan el prefijo `/api`.

| Método y ruta | Función |
| --- | --- |
| `GET /api/productos` | Devuelve los productos y las existencias actuales. |
| `GET /api/ventas` | Devuelve las últimas 50 ventas. |
| `GET /api/resumen` | Devuelve métricas de las ventas, cajeros, cola y consistencia. |
| `POST /api/ventas` | Registra y encola una venta. Responde `202 Accepted`. |
| `POST /api/ventas/simular?cantidad=20` | Genera ventas de prueba; acepta entre 1 y 100. |
| `POST /api/reiniciar` | Borra el historial y restaura el inventario si no hay ventas en curso. |

Ejemplo de cuerpo para `POST /api/ventas`:

```json
{
  "cliente": "Ana",
  "productoId": 1,
  "cantidad": 2
}
```

En PowerShell también se puede enviar así:

```powershell
Invoke-RestMethod -Method Post `
  -Uri http://localhost:8080/api/ventas `
  -ContentType "application/json" `
  -Body '{"cliente":"Ana","productoId":1,"cantidad":2}'
```

Las solicitudes inválidas devuelven `400 Bad Request`; un producto inexistente devuelve `404 Not Found`; si se intenta reiniciar mientras hay trabajo pendiente o activo, se devuelve `409 Conflict`.

## 11. Función de la interfaz

La pantalla muestra el stock actual frente al stock inicial, el número de cajeros activos, las tareas en cola, las ventas completadas y rechazadas, las unidades vendidas y la consistencia. Permite registrar una venta, simular 20 ventas y reiniciar la demostración.

La interfaz consulta el backend una vez por segundo para reflejar los cambios de estado. La tabla muestra las últimas 50 ventas, con su cliente, producto, estado, nombre del hilo y mensaje final.

## 12. Problemas frecuentes

### `password authentication failed for user "ventas"`

La contraseña del usuario de PostgreSQL no coincide. Desde pgAdmin, conectado como administrador a `postgres`, vuelve a ejecutar el bloque `DO` de `backend/local-db.sql`. La contraseña local que espera la aplicación es `ventas`.

### `no existe la base de datos "ventas"`

En pgAdmin, conectado a `postgres`, ejecuta por separado:

```sql
CREATE DATABASE ventas OWNER ventas;
```

### El puerto 8080 o 5432 ya está ocupado

Puede haber otra instancia del backend o de PostgreSQL usando el puerto. Cierra esa instancia o cambia el puerto correspondiente antes de volver a iniciar.

### La interfaz muestra que no se puede conectar

Confirma que el backend arrancó correctamente en `http://localhost:8080` y que PostgreSQL está iniciado. La interfaz necesita ambos para mostrar inventario y ventas.

## 13. Guion breve para explicar el proyecto

> Este sistema permite registrar ventas y ver cómo se procesa cada una usando concurrencia. Cuando llega una venta, el backend la guarda como pendiente y la manda a una cola atendida por un grupo fijo de hilos llamados cajeros. Cada cajero intenta descontar el inventario directamente en PostgreSQL con una actualización condicional. Así, aunque varias ventas compitan por las últimas unidades, la base de datos evita que el stock quede negativo. La interfaz consulta la API periódicamente y muestra el estado de las ventas, los cajeros activos, la cola y la consistencia del inventario.

## 14. Alcance y limitaciones

- Es una aplicación educativa y de demostración; no incluye autenticación ni gestión de usuarios.
- La espera aleatoria simula el tiempo de atención de cada cajero.
- La simulación de ventas usa nombres y cantidades de ejemplo.
- El inventario se conserva en PostgreSQL; el reset de la aplicación restaura el stock inicial y elimina el historial, siempre que no haya ventas pendientes o en curso.
- La aplicación no gestiona pagos, facturación ni conexión a un sistema comercial externo.
