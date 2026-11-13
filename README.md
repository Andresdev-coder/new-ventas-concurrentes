# Sistema de Ventas e Inventario Concurrente

Backend: Java 17 + Spring Boot 3 + PostgreSQL (hilos y pool de cajeros)
Frontend: React + Vite (se despliega en Vercel)

## Como funciona la concurrencia
- `VentaService` crea un `ThreadPoolExecutor` fijo con N trabajadores llamados `Cajero-1..N`.
- Cada solicitud aceptada se guarda como `PENDIENTE` y se entrega como tarea a ese pool.
- Si todos los cajeros están ocupados, la tarea espera en `LinkedBlockingQueue`; no se crea un hilo por venta.
- El hilo cajero cambia la venta a `EN_PROCESO`, simula la atención y luego intenta descontar el inventario.
- El `UPDATE productos SET stock = stock - ? WHERE ... AND stock >= ?` es una sola operación atómica en PostgreSQL.
  Si dos cajeros intentan vender las últimas unidades, la base serializa la actualización de esa fila y
  solo permite el descuento que todavía cumple `stock >= cantidad`.
- Al final, la venta queda `COMPLETADA` si se descontó stock o `RECHAZADA` si no había suficiente.
- La API responde `202 Accepted` al encolar la venta; eso significa que fue aceptada para procesarse,
  no que la venta ya se haya completado.
- `volatile` en estado/cajero/mensaje hace visibles en memoria los cambios entre el hilo cajero y los
  hilos HTTP. PostgreSQL conserva esos cambios para que el historial sobreviva al reinicio.
- `/api/resumen` verifica al terminar que (stock inicial - stock actual) == unidades de ventas completadas.

Para estudiar el código, sigue esta ruta: `VentaController.registrar` valida la petición,
`VentaService.registrar` guarda y encola el trabajo, `VentaService.procesar` lo ejecuta en un cajero,
y `InventarioService.descontar` resuelve de forma segura la competencia por el stock.

## Ejecutar sin Docker (Java, Maven y PostgreSQL instalados)

Docker es opcional. El backend ya está configurado para conectarse a PostgreSQL local en
`localhost:5432`, base `ventas`, usuario `ventas` y contraseña `ventas`.

1. Instala **Java 17**, **Maven 3.9+**, **PostgreSQL 16** y **Node.js 18+**.
2. Inicia el servicio de PostgreSQL. Desde pgAdmin abre Query Tool conectado a la base
   `postgres` como administrador. En `backend/local-db.sql`, ejecuta primero el bloque `DO`;
   crea el usuario `ventas` o corrige su contraseña si ya existía. Luego ejecuta `CREATE DATABASE`
   por separado solo si esa base aún no existe, ya que PostgreSQL no permite crear bases dentro
   de una transacción. La aplicación local espera el usuario y la contraseña `ventas`.
3. En una terminal de VS Code, inicia el backend:

   ```powershell
   cd backend
   mvn spring-boot:run
   ```

   Al iniciar, Spring ejecuta `schema.sql` y `data.sql`: crea las tablas y carga el inventario
   inicial. Abre `http://localhost:8080` para el backend. Mantén esa terminal abierta.

4. En una segunda terminal, inicia la interfaz:

```bash
cd frontend
npm install
npm run dev
```

Abre `http://localhost:5173`. No hay que crear `.env` para desarrollo local; la app usa la API
en `localhost:8080`. `npm install` descarga las dependencias de React y Vite.

Si PostgreSQL usa otros datos, define estas variables antes de iniciar el backend:

```powershell
$env:SPRING_DATASOURCE_URL = "jdbc:postgresql://localhost:5432/ventas"
$env:SPRING_DATASOURCE_USERNAME = "ventas"
$env:SPRING_DATASOURCE_PASSWORD = "ventas"
mvn spring-boot:run
```

Para detenerlo, presiona `Ctrl+C` en cada terminal. Si usas pgAdmin para reiniciar el inventario,
ten en cuenta que `data.sql` solo inserta productos faltantes; no repone el stock ya vendido.

## Ejecutar con Docker (opcional)

Si prefieres no instalar Java, Maven ni PostgreSQL, instala e inicia Docker Desktop y desde la
raíz del proyecto corre:

```bash
docker compose up --build
```

Esto levanta PostgreSQL en `localhost:5432` y el backend en `http://localhost:8080`. Los datos
persisten en el volumen `postgres_data`. Para detenerlos: `docker compose down`; para borrar
también la base: `docker compose down -v`.

## Endpoints
GET  /api/productos
GET  /api/ventas
GET  /api/resumen
POST /api/ventas            {"cliente":"Ana","productoId":1,"cantidad":2}
POST /api/ventas/simular?cantidad=20
POST /api/reiniciar

## Despliegue
Vercel NO ejecuta aplicaciones Java de larga duracion (es serverless), por eso:

1. Backend en Render (o Railway):
   - New Web Service -> repositorio -> Root Directory: backend -> Runtime: Docker
   - Variable de entorno: CORS_ORIGINS = https://TU-APP.vercel.app
   - Al terminar te da una URL: https://tu-backend.onrender.com
2. Frontend en Vercel:
   - Import Project -> Root Directory: frontend (Framework: Vite)
   - Variable de entorno: VITE_API_URL = https://tu-backend.onrender.com
   - Deploy

En Render/Railway configura tambien `SPRING_DATASOURCE_URL`, `SPRING_DATASOURCE_USERNAME` y
`SPRING_DATASOURCE_PASSWORD` con las credenciales de una base PostgreSQL administrada.

Nota: el plan gratis de Render duerme el servicio tras inactividad; la primera
peticion puede tardar cerca de 1 minuto. Abrelo antes de la sustentacion.
