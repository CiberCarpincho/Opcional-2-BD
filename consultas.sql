
--consulta 1 paises que no tienen litoral
SELECT
    c.Name AS Country_Name
FROM
    Country c
WHERE
    NOT EXISTS (
        SELECT 1
        FROM geo_Sea gs
        WHERE gs.Country = c.Code
    )
  AND c.Code IS NOT NULL
ORDER BY
    c.Name;

--consulta 2: rios que pasan por mas de un pais
SELECT
    gr.River AS River_Name,
    COUNT(DISTINCT gr.Country) AS Number_Of_Countries,
    STRING_AGG(DISTINCT c.Name, ', ') AS Countries,
    STRING_AGG(DISTINCT gr.Country, ', ') AS Country_Codes,
    r.Length,
    r.Area AS River_Basin_Area
FROM
    geo_River gr
        JOIN
    River r ON gr.River = r.Name
        JOIN
    Country c ON gr.Country = c.Code
GROUP BY
    gr.River, r.Length, r.Area
HAVING
    COUNT(DISTINCT gr.Country) > 1
ORDER BY
    Number_Of_Countries DESC,
    River_Name;


-- consulta 3: Continentes con mayor densidad poblacional
SELECT
    ct.Name AS Continent_Name,
    ct.Area AS Continent_Area,
    SUM(c.Population) AS Total_Population,
    ROUND(SUM(c.Population) / NULLIF(ct.Area, 0), 2) AS Population_Density,
    COUNT(DISTINCT c.Code) AS Number_Of_Countries,
    ROUND(AVG(e.GDP / NULLIF(c.Population, 0)), 2) AS Avg_GDP_Per_Capita
FROM
    Continent ct
        JOIN
    encompasses en ON ct.Name = en.Continent
        JOIN
    Country c ON en.Country = c.Code
        LEFT JOIN
    Economy e ON c.Code = e.Country
WHERE
    c.Population > 0
  AND ct.Area > 0
GROUP BY
    ct.Name, ct.Area
ORDER BY
    Population_Density DESC;

--docker run -it -ePOSTGRES_USER=postgres -e POSTGRES_PASSWORD=pinito2 -p 5432:5432 postgres:15
--docker run -p 5050:80 -e "PGADMIN_DEFAULT_EMAIL=admin@admin.com" -e "PGADMIN_DEFAULT_PASSWORD=pg123" dpage/pgadmin4
--ipconfig 192.168.1.3
--http://localhost:5050