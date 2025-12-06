-- ============================================
-- VISTAS, FUNCIONES, PROCEDIMIENTOS Y TRIGGERS
-- Base de Datos Geográfica
-- ============================================

-- 1. Vista de países con alto PIB per cápita
-- Esta vista identifica los países con un PIB per cápita superior a $30,000 USD,
-- mostrando información económica y poblacional para análisis comparativo.
-- Útil para estudios de desarrollo económico y clasificación de países por riqueza.
CREATE OR REPLACE VIEW HighGDPPerCapita AS
SELECT
    c.Name AS Country_Name,
    c.Code AS Country_Code,
    c.Population,
    e.GDP,
    ROUND(e.GDP / NULLIF(c.Population, 0), 2) AS GDP_Per_Capita
FROM
    Country c
        JOIN
    Economy e ON c.Code = e.Country
WHERE
    (e.GDP / NULLIF(c.Population, 0)) > 30000
ORDER BY
    GDP_Per_Capita DESC;

-- 2. Vista de ciudades costeras
-- Identifica ciudades que están ubicadas junto al mar, mostrando información
-- geográfica y el nombre del mar al que tienen acceso. Es útil para estudios
-- de logística portuaria, turismo costero y planificación urbana en zonas litorales.
CREATE OR REPLACE VIEW CoastalCities AS
SELECT DISTINCT
    ci.Name AS City_Name,
    ci.Country AS Country_Code,
    ci.Province,
    ci.Population,
    ci.Latitude,
    ci.Longitude,
    s.Name AS Sea_Name
FROM
    City ci
        JOIN
    located l ON ci.Name = l.City
        AND ci.Country = l.Country
        AND ci.Province = l.Province
        JOIN
    Sea s ON l.Sea = s.Name
WHERE
    l.Sea IS NOT NULL
ORDER BY
    ci.Country, ci.Name;

-- 3. Vista de países con múltiples continentes
-- Lista los países cuyos territorios se extienden por más de un continente,
-- como Rusia (Europa/Asia) o Turquía (Europa/Asia). Muestra el número de
-- continentes y el porcentaje total de territorio en cada uno.
CREATE OR REPLACE VIEW MultiContinentCountries AS
SELECT
    c.Name AS Country_Name,
    c.Code AS Country_Code,
    COUNT(DISTINCT en.Continent) AS Number_Of_Continents,
    STRING_AGG(en.Continent, ', ') AS Continents,
    SUM(en.Percentage) AS Total_Percentage
FROM
    Country c
        JOIN
    encompasses en ON c.Code = en.Country
GROUP BY
    c.Name, c.Code
HAVING
    COUNT(DISTINCT en.Continent) > 1
ORDER BY
    Number_Of_Continents DESC;

-- 4. Función: calcular crecimiento poblacional anual
-- Calcula la tasa de crecimiento poblacional anual compuesta entre dos años
-- para un país específico. Utiliza la fórmula de CAGR (Compound Annual Growth Rate).
-- Retorna el porcentaje de crecimiento anual promedio.
-- Parámetros: código del país, año inicial, año final
-- Ejemplo: SELECT CalculatePopulationGrowth('USA', 2010, 2020);
CREATE OR REPLACE FUNCTION CalculatePopulationGrowth(
    country_code VARCHAR(4),
    year1 DECIMAL,
    year2 DECIMAL
)
RETURNS DECIMAL AS $$
DECLARE
pop1 DECIMAL;
    pop2 DECIMAL;
    growth_rate DECIMAL;
BEGIN
    -- Obtener población del año inicial
SELECT Population INTO pop1
FROM Countrypops
WHERE Country = country_code AND Year = year1;

-- Obtener población del año final
SELECT Population INTO pop2
FROM Countrypops
WHERE Country = country_code AND Year = year2;

-- Verificar que existan datos para ambos años
IF pop1 IS NULL OR pop2 IS NULL THEN
        RETURN NULL;
END IF;

    -- Calcular tasa de crecimiento (evitar división por cero)
    IF pop1 = 0 THEN
        RETURN NULL;
ELSE
        -- Fórmula: ((P2/P1)^(1/(t2-t1)) - 1) * 100
        growth_rate := ((pop2 / pop1) ^ (1 / (year2 - year1)) - 1) * 100;
RETURN ROUND(growth_rate, 2);
END IF;
END;
$$ LANGUAGE plpgsql;

-- 5. Función: distancia aproximada entre dos ciudades
-- Calcula la distancia en kilómetros entre dos ciudades usando la fórmula
-- del Haversine, que considera la curvatura de la Tierra.
-- Requiere las coordenadas geográficas de ambas ciudades (latitud/longitud).
-- Parámetros: nombre, país y provincia de ambas ciudades
-- Ejemplo: SELECT CalculateDistance('Madrid', 'E', 'Madrid', 'Barcelona', 'E', 'Cataluña');
CREATE OR REPLACE FUNCTION CalculateDistance(
    city1_name VARCHAR(50),
    city1_country VARCHAR(4),
    city1_province VARCHAR(50),
    city2_name VARCHAR(50),
    city2_country VARCHAR(4),
    city2_province VARCHAR(50)
)
RETURNS DECIMAL AS $$
DECLARE
lat1 DECIMAL;
    lon1 DECIMAL;
    lat2 DECIMAL;
    lon2 DECIMAL;
    distance DECIMAL;
    earth_radius CONSTANT DECIMAL := 6371; -- Radio terrestre en kilómetros
BEGIN
    -- Obtener coordenadas de la primera ciudad
SELECT Latitude, Longitude INTO lat1, lon1
FROM City
WHERE Name = city1_name
  AND Country = city1_country
  AND Province = city1_province;

-- Obtener coordenadas de la segunda ciudad
SELECT Latitude, Longitude INTO lat2, lon2
FROM City
WHERE Name = city2_name
  AND Country = city2_country
  AND Province = city2_province;

-- Verificar que ambas ciudades existan en la base de datos
IF lat1 IS NULL OR lat2 IS NULL THEN
        RETURN NULL;
END IF;

    -- Convertir grados decimales a radianes (requerido por la fórmula)
    lat1 := radians(lat1);
    lon1 := radians(lon1);
    lat2 := radians(lat2);
    lon2 := radians(lon2);

    -- Aplicar fórmula del Haversine para calcular distancia
    distance := earth_radius * ACOS(
        SIN(lat1) * SIN(lat2) +
        COS(lat1) * COS(lat2) * COS(lon1 - lon2)
    );

RETURN ROUND(distance, 2);
END;
$$ LANGUAGE plpgsql;

-- 6. Procedimiento: insertar una ciudad con validación
-- Procedimiento seguro para insertar nuevas ciudades con validaciones exhaustivas:
-- 1. Verifica que el país exista
-- 2. Verifica que la provincia exista en ese país
-- 3. Valida que la población no sea negativa
-- 4. Valida rangos de coordenadas geográficas
-- 5. Verifica que no exista una ciudad con el mismo nombre en la misma provincia
-- Además, actualiza automáticamente las poblaciones de provincia y país.
CREATE OR REPLACE PROCEDURE InsertCityWithValidation(
    city_name VARCHAR(50),
    country_code VARCHAR(4),
    province_name VARCHAR(50),
    city_population DECIMAL,
    city_latitude DECIMAL,
    city_longitude DECIMAL,
    city_elevation DECIMAL DEFAULT NULL
)
AS $$
BEGIN
    -- Validar que el país existe
    IF NOT EXISTS (SELECT 1 FROM Country WHERE Code = country_code) THEN
        RAISE EXCEPTION 'El país con código % no existe', country_code;
END IF;

    -- Validar que la provincia existe para ese país
    IF NOT EXISTS (SELECT 1 FROM Province WHERE Name = province_name AND Country = country_code) THEN
        RAISE EXCEPTION 'La provincia % no existe en el país %', province_name, country_code;
END IF;

    -- Validar población no negativa
    IF city_population < 0 THEN
        RAISE EXCEPTION 'La población no puede ser negativa: %', city_population;
END IF;

    -- Validar coordenadas (latitud entre -90 y 90, longitud entre -180 y 180)
    IF city_latitude < -90 OR city_latitude > 90 THEN
        RAISE EXCEPTION 'Latitud fuera de rango: % (debe estar entre -90 y 90)', city_latitude;
END IF;

    IF city_longitude < -180 OR city_longitude > 180 THEN
        RAISE EXCEPTION 'Longitud fuera de rango: % (debe estar entre -180 y 180)', city_longitude;
END IF;

    -- Validar que la ciudad no exista ya (clave primaria compuesta)
    IF EXISTS (
        SELECT 1 FROM City
        WHERE Name = city_name
            AND Country = country_code
            AND Province = province_name
    ) THEN
        RAISE EXCEPTION 'La ciudad % ya existe en %/%', city_name, province_name, country_code;
END IF;

    -- Insertar la ciudad con los datos validados
INSERT INTO City (Name, Country, Province, Population, Latitude, Longitude, Elevation)
VALUES (city_name, country_code, province_name, city_population, city_latitude, city_longitude, city_elevation);

RAISE NOTICE 'Ciudad % insertada exitosamente', city_name;

    -- Actualizar la población de la provincia (sumar nueva población)
UPDATE Province
SET Population = Population + city_population
WHERE Name = province_name AND Country = country_code;

-- Actualizar la población del país (sumar nueva población)
UPDATE Country
SET Population = Population + city_population
WHERE Code = country_code;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error al insertar ciudad: %', SQLERRM;
END;
$$ LANGUAGE plpgsql;

-- 7. Trigger: prevenir población negativa
-- Función de trigger que impide la inserción o actualización de registros
-- con población negativa en la tabla City. Se activa automáticamente antes
-- de cada operación INSERT o UPDATE, garantizando la integridad de los datos.

-- Primero creamos la función que implementa la lógica del trigger
CREATE OR REPLACE FUNCTION prevent_negative_population()
RETURNS TRIGGER AS $$
BEGIN
    -- Verificar si el nuevo valor de población es negativo
    IF NEW.Population < 0 THEN
        -- Lanzar excepción que cancela la operación
        RAISE EXCEPTION 'La población no puede ser negativa. Valor intentado: %', NEW.Population;
END IF;
    -- Si la población es válida, permitir la operación
RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Creamos el trigger que asocia la función a la tabla City
-- Se ejecuta BEFORE (antes) de INSERT o UPDATE en cada fila (FOR EACH ROW)
CREATE TRIGGER trigger_prevent_negative_population
    BEFORE INSERT OR UPDATE ON City
                         FOR EACH ROW
                         EXECUTE FUNCTION prevent_negative_population();


/*
-- Ejemplo de uso de la vista de alto PIB per cápita
SELECT * FROM HighGDPPerCapita LIMIT 10;

-- Ejemplo de uso de la vista de ciudades costeras
SELECT * FROM CoastalCities WHERE Country_Code = 'E';

-- Ejemplo de uso de la vista de países multcontinentales
SELECT * FROM MultiContinentCountries;

-- Ejemplo de uso de la función de crecimiento poblacional
SELECT CalculatePopulationGrowth('USA', 2010, 2020) AS Crecimiento_Anual_Porcentaje;

-- Ejemplo de uso de la función de distancia
SELECT CalculateDistance('Madrid', 'E', 'Madrid', 'Barcelona', 'E', 'Cataluña') AS Distancia_km;

-- Ejemplo de uso del procedimiento para insertar ciudad
CALL InsertCityWithValidation(
    'NuevaCiudad',      -- city_name
    'E',               -- country_code
    'Madrid',          -- province_name
    50000,             -- city_population
    40.4168,           -- city_latitude (Madrid)
    -3.7038,           -- city_longitude (Madrid)
    650                -- city_elevation (metros)
);

-- Prueba del trigger (debería fallar)
-- INSERT INTO City VALUES ('CiudadTest', 'E', 'Madrid', -1000, 40.0, -3.0, 600);
*/