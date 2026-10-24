# Política de Seguridad

La seguridad es el núcleo de este proyecto de laboratorio SOC L2. Nos tomamos muy en serio la protección de las configuraciones, la infraestructura en la nube y los datos de cualquier usuario o entorno de prueba.

---

## Versiones con soporte

Actualmente, solo la rama principal activa (`main` / `master`) y las versiones de lanzamiento más recientes reciben revisiones y parches de seguridad:

| Versión | ¿Soportada? |
| :--- | :--- |
| Rama `main` (código fuente actual) | :white_check_mark: Sí |
| Versiones anteriores / ramas de trabajo | :x: No |

---

## Reportar una vulnerabilidad

**POR FAVOR, NO REPORTES VULNERABILIDADES DE SEGURIDAD MEDIANTE ISSUES PÚBLICOS.**

Si identificas una vulnerabilidad de seguridad (por ejemplo: exposición involuntaria de credenciales, configuración de red riesgosa por defecto, inyección en scripts o desbordamiento de permisos en Azure RBAC):

1. **Usa GitHub Private Vulnerability Reporting** (si está habilitado en este repositorio):
   - Ve a la pestaña **Security** del repositorio.
   - Haz clic en **Report a vulnerability** para abrir un aviso confidencial.
2. **O contacta privadamente al mantenedor del proyecto** mediante los canales de contacto provistos en el perfil del mantenedor en GitHub.

### Información útil a incluir en el reporte:
- Descripción detallada de la vulnerabilidad o falla de configuración.
- Pasos precisos o código Terraform / KQL para reproducir el problema.
- Escenario de impacto potencial (ej. elevación de privilegios, denegación de servicio, exposición pública de recursos).
- Propuesta de mitigación o parche sugerido (si lo tienes).

---

## Compromiso y tiempos de respuesta

- **Confirmación inicial:** Acuse de recibo en un plazo máximo de 48 a 72 horas laborales.
- **Evaluación y remediación:** Se evaluará la severidad y se coordinará una solución mediante una rama privada o parche de seguridad.
- **Divulgación pública:** Se realizará una vez publicado el parche correctivo para que los usuarios puedan actualizar de forma segura.

---

## Buenas prácticas recomendadas para usuarios del laboratorio

1. **Nunca subas credenciales reales**: No confirmes archivos `terraform.tfstate`, `*.tfvars` con valores reales, claves privadas SSH ni contraseñas de cuentas de servicio al control de versiones.
2. **Restricción de NSG e IPs de acceso**: Por defecto, limita los accesos RDP/SSH en [network.tf](network.tf) a tu dirección IP pública de administración en lugar de `0.0.0.0/0`.
3. **Destrucción de recursos al finalizar prácticas**: Recuerda ejecutar `terraform destroy` o detener las instancias para evitar costos no deseados o superficies de ataque expuestas innecesariamente.
