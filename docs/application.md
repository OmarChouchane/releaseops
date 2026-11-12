# The application

The Crewmeister challenge service: Spring Boot, MySQL, Flyway.

The API is the one in the challenge; behaviour is unchanged except the small, documented items in
[ADR-0002](adr/0002-spring-boot-upgrade.md).

| Request | Response |
|---|---|
| `POST /user` `{"name":"Ada"}` | `200`, body `Greetings from Crewmeister, Ada!`, header `Location: /user?id=<id>` |
| `GET /user?id=1` | `200`, `Greetings from Crewmeister, Alice!` (row seeded by Flyway) |
| `GET /user?id=999999` | `404` (was `500`) |
| `GET /user` (no id) | `400` |
| `POST /user` with invalid JSON | `200` `Error parsing JSON` — legacy behaviour, kept and pinned by a test |

```bash
curl -si -X POST localhost:18080/user -H 'Content-Type: application/json' -d '{"name":"Ada"}'
curl -s 'localhost:18080/user?id=1'
```

Run the app without Kubernetes: start a MySQL, then `./mvnw spring-boot:run` (defaults to `root/dev@localhost:3306`).
