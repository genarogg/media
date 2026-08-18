import React from "react";
import { 
      A,
      BR,
      Badge,
      Col4,
      Container,
      Div,
      H4,
      H6,
      HR,
      Img,
      LI,
      Layout,
      P,
      Row,
      Span,
      UL
    } from "@react-pdf-levelup/core";


// ────────────────────────────────────────────────────────────
// Tipos de datos
// ────────────────────────────────────────────────────────────

interface ExperienciaProfesional {
  company: string;
  role: string;
  description: string;
}

interface ProyectoDestacado {
  number: string;
  title: string;
  stack: string[];
  summary: string;
  highlights: string[];
  result?: string;
  url?: string;
  link?: string;
}

interface StackCategoria {
  category: string;
  technologies: string[];
}

interface DatosPersonales {
  nombre: string;
  titulo: string;
  cedula: string;
  email: string;
  telefono: string;
  github: string;
  linkedin: string;
  ubicacion: string;
  avatarUrl: string;
}

interface ComponentData {
  personal: DatosPersonales;
  perfilProfesional: string[];
  experienciaProfesional: ExperienciaProfesional[];
  proyectosDestacados: ProyectoDestacado[];
  stackTecnico: StackCategoria[];
}

// ────────────────────────────────────────────────────────────
// Datos por defecto (usados si no se pasa `data`)
// ────────────────────────────────────────────────────────────

const experienciaProfesionalDefault: ExperienciaProfesional[] = [
  {
    company: "Universidad Nacional Experimental Rómulo Gallegos (UNERG)",
    role: "Analista · Desarrollador · Mantenedor de Sistemas",
    description:
      "Desarrollo y mantenimiento de sistemas institucionales orientados a procesos académicos y administrativos, participando en el análisis, diseño, implementación de módulos, automatización de procesos e integración con servicios y sistemas existentes.",
  },
  {
    company: "Colegio de Optometristas de Venezuela (COV)",
    role: "Analista · Desarrollador · Mantenedor de Sistemas",
    description:
      "Desarrollo y mantenimiento de sistemas y plataformas digitales para la gestión de procesos institucionales, participando en el análisis de requerimientos, desarrollo de funcionalidades, integración de APIs y bases de datos y resolución de incidencias.",
  },
  {
    company: "Bloom 4All",
    role: "Desarrollador Web",
    description:
      "Desarrollo de sitios web para clientes de la agencia, incluyendo implementación de interfaces responsive, integración de contenido, mantenimiento de sitios existentes y optimización de la experiencia de usuario.",
  },
  {
    company: "El Tubazo Digital",
    role: "Administrador / Mantenedor de Servidores",
    description:
      "Mantenimiento de servidores y servicios utilizados por el periódico digital, incluyendo resolución de incidencias, configuración de servicios y soporte de infraestructura.",
  },
  {
    company: "24 Noticias Digital",
    role: "Administrador / Mantenedor de Servidores",
    description:
      "Mantenimiento y soporte de la infraestructura tecnológica del medio digital, incluyendo administración de servicios, resolución de incidencias y mantenimiento de servidores.",
  },
];

const proyectosDestacadosDefault: ProyectoDestacado[] = [
  {
    number: "01",
    title: "Sistema de Solicitud de Documentos — UNERG",
    stack: ["Next.js", "React", "Node.js", "Fastify", "GraphQL", "Prisma", "PostgreSQL", "Docker"],
    summary:
      "Plataforma web desarrollada para digitalizar el proceso de solicitud y entrega de documentos académicos de la Universidad Nacional Experimental Rómulo Gallegos (UNERG). El proyecto reemplazó un proceso que anteriormente requería gestiones presenciales y podía tardar varios meses.",
    highlights: [
      "Diseño y desarrollo de la arquitectura completa del sistema.",
      "Implementación del flujo de solicitudes, validación, procesamiento y entrega.",
      "Sistema de roles y permisos para estudiantes, asistentes y administradores.",
      "Automatización del cálculo y actualización de costos mediante la tasa de cambio oficial.",
      "Generación de documentos y reportes PDF con códigos QR de verificación.",
      "Notificaciones automáticas por correo.",
      "Bitácora de auditoría de las operaciones realizadas.",
      "Despliegue mediante Docker y Docker Compose.",
    ],
    result: "Reducción del tiempo de entrega de documentos de varios meses a aproximadamente 3 semanas.",
    link: "https://solicitudes.unerg.edu.ve",
  },
  {
    number: "02",
    title: "Sistema de Recursos Humanos — UNERG",
    stack: ["Next.js", "React", "Node.js", "Fastify", "GraphQL", "Prisma", "PostgreSQL", "Docker"],
    summary:
      "Plataforma de autoservicio desarrollada para el departamento de Recursos Humanos de la UNERG, permitiendo a los trabajadores solicitar documentos administrativos sin realizar el trámite presencialmente. El sistema gestiona constancias de trabajo, constancias de sueldo, carnet institucional, ARC y recibos de pago.",
    highlights: [
      "Desarrollo completo de frontend, backend y base de datos.",
      "Sistema de autenticación y roles para administradores, asistentes y trabajadores.",
      "Integración con la base de datos legacy de nómina y contabilidad.",
      "Generación automática de documentos PDF con firma digital y códigos QR.",
      "Notificaciones automáticas por correo.",
      "Registro de auditoría de las operaciones del sistema.",
      "Implementación de medidas de seguridad y control de acceso.",
      "Despliegue mediante Docker y Docker Compose.",
    ],
    result:
      "Digitalización de un proceso anteriormente presencial, reduciendo la carga operativa del departamento y mejorando la trazabilidad de las solicitudes.",
    link: "https://rrhh.unerg.edu.ve",
  },
  {
    number: "03",
    title: "Plataforma de gestión — Colegio de Optometristas de Venezuela",
    stack: ["Next.js", "Fastify", "Apollo Server", "Prisma", "PostgreSQL"],
    summary:
      "Plataforma desarrollada para centralizar los procesos administrativos del Colegio de Optometristas de Venezuela, permitiendo gestionar servicios y trámites completamente en línea. Incluye inscripción, eventos, carnetización, pagos y gestión documental.",
    highlights: [
      "Desarrollo del backend con Fastify, Apollo Server y Prisma.",
      "Diseño e integración de PostgreSQL.",
      "Implementación de APIs GraphQL.",
      "Desarrollo del frontend con Next.js.",
      "Sistema de usuarios y permisos.",
      "Dashboard para gestión de trámites.",
      "Flujos de selección y compra.",
      "Integración entre los diferentes módulos de la plataforma.",
    ],
    url: "https://covoficial.org/",
  },
  {
    number: "04",
    title: "react-pdf-levelup",
    stack: ["React", "TypeScript", "Node.js", "Vite", "Fastify", "Monaco Editor"],
    summary:
      "Ecosistema de generación programática de PDFs mediante componentes React reutilizables, compuesto por una librería core, IDE de desarrollo, documentación y playground.",
    highlights: [
      "Componentes para tablas, códigos QR, códigos de barras y gráficos.",
      "Sistema de fuentes y gradientes.",
      "Renderizado asíncrono compatible con Node.js y navegador.",
      "Generación de PDFs desde backend.",
      "Procesamiento paralelo mediante worker threads y Piscina.",
      "IDE basado en React, Vite, Fastify y Monaco Editor.",
      "Documentación bilingüe con Astro/Starlight.",
      "Playground interactivo con editor y visor de PDF.",
    ],
    url: "https://react-pdf-levelup.nimbux.cloud",
  },
  {
    number: "05",
    title: "Pipeline de migración de datos académicos",
    stack: ["Node.js", "TypeScript", "DBF", "PostgreSQL", "Prisma"],
    summary:
      "Pipeline desarrollado para migrar datos académicos desde sistemas universitarios heredados basados en archivos DBF hacia PostgreSQL, diseñado para procesar grandes volúmenes de información sin cargar todos los registros en memoria.",
    highlights: [
      "Procesamiento de archivos DBF.",
      "Pipeline desarrollado en Node.js y TypeScript.",
      "Migración hacia PostgreSQL mediante Prisma.",
      "Estrategia de carga invertida para optimizar memoria.",
      "Upsert atómico para evitar inconsistencias.",
      "Uso de INSERT ... ON CONFLICT DO UPDATE.",
    ],
  },
  {
    number: "06",
    title: "supermoney",
    stack: ["JavaScript Vanilla"],
    summary:
      "Librería propia desarrollada para trabajar con montos monetarios evitando problemas derivados de la representación de números decimales en JavaScript. Utiliza internamente valores enteros expresados en centavos.",
    highlights: [],
    url: "https://super-money.nimbux.cloud",
  },
];

const stackTecnicoDefault: StackCategoria[] = [
  {
    category: "Frontend",
    technologies: ["JavaScript", "TypeScript", "React", "Next.js", "HTML5", "CSS3", "Sass", "Tailwind CSS"],
  },
  {
    category: "Backend",
    technologies: ["Node.js", "Fastify", "Express.js", "REST", "GraphQL", "Apollo Server"],
  },
  {
    category: "Bases de datos",
    technologies: ["PostgreSQL", "MariaDB", "MySQL", "SQLite"],
  },
  {
    category: "ORM",
    technologies: ["Prisma", "Sequelize"],
  },
  {
    category: "Arquitectura",
    technologies: [
      "MVC",
      "Arquitectura por capas",
      "Arquitectura hexagonal",
      "Diseño modular",
      "Arquitectura basada en componentes",
    ],
  },
  {
    category: "Infraestructura",
    technologies: ["Docker", "Docker Compose", "Administración de servidores", "Despliegue de aplicaciones"],
  },
  {
    category: "Otros",
    technologies: ["PHP", "CakePHP", "Java", "Python", "ElectronJS", "CapacitorJS"],
  },
];

const perfilProfesionalDefault: string[] = [
  "Ingeniero Informático y Full Stack Developer especializado en JavaScript/TypeScript, con más de 8 años de experiencia en desarrollo de software.",
  "Experiencia construyendo aplicaciones de extremo a extremo, desde el análisis de requerimientos, arquitectura y bases de datos hasta el desarrollo de APIs e interfaces con React y Next.js.",
  "He trabajado en proyectos para instituciones educativas, organizaciones profesionales, medios de comunicación y agencias de marketing, participando en el desarrollo, mantenimiento y evolución de sistemas.",
  "Especializado en crear software modular, mantenible y orientado al rendimiento, con experiencia adicional en generación de documentos, migración de datos, administración de servidores y despliegue de aplicaciones.",
];

const datosPersonalesDefault: DatosPersonales = {
  nombre: "Genaro Octavio Gonzalez Gonzalez",
  titulo: "INGENIERO INFORMÁTICO · FULL STACK DEVELOPER",
  cedula: "V-25074591",
  email: "genarrogg@gmail.com",
  telefono: "+584127554970",
  github: "genarogg",
  linkedin: "genarogg",
  ubicacion: "Maracay, Venezuela. (Disponibilidad para reubicación)",
  avatarUrl: "https://genarogg.github.io/media/genarogg/avatar-left.jpg",
};

const dataDefault: ComponentData = {
  personal: datosPersonalesDefault,
  perfilProfesional: perfilProfesionalDefault,
  experienciaProfesional: experienciaProfesionalDefault,
  proyectosDestacados: proyectosDestacadosDefault,
  stackTecnico: stackTecnicoDefault,
};

// ────────────────────────────────────────────────────────────
// Estilos (extraídos como objetos nombrados)
// ────────────────────────────────────────────────────────────

const styles = {
  layout: {
    color: "#040613",
    backgroundColor: "#ffffff",
  },
  nombre: {
    color: "#0f172a",
  },
  titulo: {
    color: "#27aae8",
  },
  avatarWrapper: {
    borderRadius: 50,
    border: "2px solid #2563eb",
    position: "absolute",
    right: 35,
  },
  avatarImg: {
    borderRadius: 50,
  },
  dividerFuerte: {
    borderTop: "3px solid #e2e8f0",
  },
  dividerTitulo: {
    borderTop: "2px solid #27aae8",
  },
  tituloSnippetWrapper: {
    marginTop: 10,
    marginBottom: 10,
  },
  tituloSnippetTexto: {
    color: "#0369a2",
    textTransform: "uppercase",
  },
  ubicacionItem: {
    maxWidth: 130,
  },
  experienciaWrapper: {
    marginBottom: 12,
  },
  experienciaEmpresa: {
    color: "#0f172a",
    marginBottom: 3,
  },
  experienciaRol: {
    color: "#0369a2",
    fontSize: 10,
    marginBottom: 4,
  },
  experienciaDescripcion: {
    color: "#334155",
    fontSize: 10,
    lineHeight: 1.4,
  },
  proyectoWrapper: {
    marginBottom: 16,
  },
  proyectoTitulo: {
    color: "#0369a2",
    marginBottom: 2,
  },
  proyectoStack: {
    color: "#64748b",
    fontSize: 8,
    marginBottom: 5,
  },
  proyectoResumen: {
    color: "#334155",
    fontSize: 10,
    lineHeight: 1.4,
    marginBottom: 5,
  },
  proyectoHighlightsLista: {
    marginTop: 3,
    marginBottom: 5,
  },
  proyectoHighlightItem: {
    fontSize: 9.5,
    color: "#475569",
    marginBottom: 2,
  },
  proyectoResultado: {
    color: "#0369a2",
    fontSize: 8.5,
    marginTop: 0,
  },
  proyectoResultadoLabel: {
    color: "#0369a2",
    fontSize: 8.5,
    fontWeight: 700,
    marginTop: 4,
    marginBottom: 0,
  },
  proyectoUrl: {
    fontSize: 8,
    color: "#2563eb",
  },
  stackCategoriaWrapper: {
    marginBottom: 8,
  },
  stackCategoriaLabel: {
    color: "#0369a2",
    fontSize: 9,
    marginBottom: 2,
  },
  stackCategoriaTecnologias: {
    color: "#334155",
    fontSize: 8.5,
    lineHeight: 1.4,
  },
} as const;

// ────────────────────────────────────────────────────────────
// Subcomponente: título de sección con línea divisoria
// ────────────────────────────────────────────────────────────

interface TituloSnippetProps {
  text: string;
}

const TituloSnippet: React.FC<TituloSnippetProps> = ({ text }) => {
  return (
    <Div style={styles.tituloSnippetWrapper}>
      <H6 style={styles.tituloSnippetTexto}>{text}</H6>
      <HR style={styles.dividerTitulo} />
    </Div>
  );
};

// ────────────────────────────────────────────────────────────
// Subcomponente: bloque de experiencia profesional
// ────────────────────────────────────────────────────────────

interface ExperienciaItemProps {
  experiencia: ExperienciaProfesional;
}

const ExperienciaItem: React.FC<ExperienciaItemProps> = ({ experiencia }) => {
  return (
    <Div style={styles.experienciaWrapper}>
      <H6 style={styles.experienciaEmpresa}>{experiencia.company}</H6>
      <P style={styles.experienciaRol}>{experiencia.role}</P>
      <P style={styles.experienciaDescripcion}>{experiencia.description}</P>
    </Div>
  );
};

// ────────────────────────────────────────────────────────────
// Subcomponente: bloque de proyecto destacado
// ────────────────────────────────────────────────────────────

interface ProyectoItemProps {
  proyecto: ProyectoDestacado;
}

const ProyectoItem: React.FC<ProyectoItemProps> = ({ proyecto }) => {
  const enlace = proyecto.url ?? proyecto.link;

  return (
    <Div style={styles.proyectoWrapper}>
      <Div>
        <H6 style={styles.proyectoTitulo}>
          {proyecto.number} · {proyecto.title}
        </H6>
      
       <Badge variant="info"  style={{ alignSelf: 'flex-start' }}>
     
        <P style={{...styles.proyectoStack}}>
        {proyecto.stack.join(" · ")}
     
        </P>
     
    </Badge>
 
      </Div>

      <P style={styles.proyectoResumen}>{proyecto.summary}</P>

      {proyecto.highlights.length > 0 && (
        <UL style={styles.proyectoHighlightsLista}>
          {proyecto.highlights.map((highlight, index) => (
            <LI key={`${proyecto.number}-highlight-${index}`} style={styles.proyectoHighlightItem}>
              {highlight}
            </LI>
          ))}
        </UL>
      )}

      {proyecto.result && (
        <>
          <P style={styles.proyectoResultadoLabel}>Resultado:</P>
          <P style={styles.proyectoResultado}>{proyecto.result}</P>
        </>
      )}

      {enlace && (
        <A href={enlace} style={styles.proyectoUrl}>
          {enlace}
        </A>
      )}
    </Div>
  );
};

// ────────────────────────────────────────────────────────────
// Subcomponente: bloque de categoría del stack técnico
// ────────────────────────────────────────────────────────────

interface StackCategoriaItemProps {
  grupo: StackCategoria;
}

const StackCategoriaItem: React.FC<StackCategoriaItemProps> = ({ grupo }) => {
  return (
    <Div style={styles.stackCategoriaWrapper}>
      <P style={styles.stackCategoriaLabel}>{grupo.category}</P>
      <P style={styles.stackCategoriaTecnologias}>{grupo.technologies.join(" · ")}</P>
    </Div>
  );
};

// ────────────────────────────────────────────────────────────
// Componente principal
// ────────────────────────────────────────────────────────────

interface ComponentProps {
  data?: ComponentData;
}

const Component: React.FC<ComponentProps> = ({ data = dataDefault }) => {
  const { personal, perfilProfesional, experienciaProfesional, proyectosDestacados, stackTecnico } = data;

  return (
    <Layout style={styles.layout}>
      <H4 style={styles.nombre}>{personal.nombre}</H4>
      <H6 style={styles.titulo}>{personal.titulo}</H6>

      <Div style={styles.avatarWrapper}>
        <Img style={styles.avatarImg} width={80} src={personal.avatarUrl} />
      </Div>

      <BR />

      <Container>
        <Row>
          <Col4>
            <UL>
              <LI><Span>Cédula: {personal.cedula}</Span></LI>
              <LI>
                <A href={`mailto:${personal.email}`}>{personal.email}</A>
              </LI>
              <LI>
                <A href={`tel:${personal.telefono}`}>Tel: {personal.telefono}</A>
              </LI>
            </UL>
          </Col4>
          <Col4>
            <UL>
              <LI>
                <A href={`https://github.com/${personal.github}`}>Github: @{personal.github}</A>
              </LI>
              <LI>
                <A href={`https://www.linkedin.com/in/${personal.linkedin}`}>Linkedin: @{personal.linkedin}</A>
              </LI>
              <LI style={styles.ubicacionItem}>{personal.ubicacion}</LI>
            </UL>
          </Col4>
        </Row>
      </Container>

      <HR style={styles.dividerFuerte} />

      <TituloSnippet text="PERFIL PROFESIONAL" />

      <Div>
        {perfilProfesional.map((parrafo, index) => (
          <P key={`perfil-${index}`}>{parrafo}</P>
        ))}
      </Div>

      <TituloSnippet text="Experiencia profesional" />

      {experienciaProfesional.map((experiencia, index) => (
        <ExperienciaItem key={`${experiencia.company}-${index}`} experiencia={experiencia} />
      ))}

      <TituloSnippet text="PROYECTOS DESTACADOS" />

      {proyectosDestacados.map((proyecto) => (
        <ProyectoItem key={proyecto.number} proyecto={proyecto} />
      ))}

      <TituloSnippet text="STACK TÉCNICO" />

      {stackTecnico.map((grupo) => (
        <StackCategoriaItem key={grupo.category} grupo={grupo} />
      ))}
    </Layout>
  );
};

export default Component;