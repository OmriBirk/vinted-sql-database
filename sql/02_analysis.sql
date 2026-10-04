-- Analysis queries for the marketplace database: joins, nested queries, window functions, CTE,
-- views, functions, a stored procedure, a trigger and index-based optimization.
-- Run 01_schema.sql first and load the sample data (see README). Hebrew comments are the original ones.

USE VintedDB;
GO


-- ==================== Queries without nesting ====================
--------------------שתי שאילתות ללא קינון 
-- 10 המוצרים היקרים שנקנו בשנת 2025
select TOP 10 S.Seller, P.ProductID, B.Buyer, O.FinalPrice
from SELLERS AS S JOIN PRODUCTS AS P ON P.Seller=S.Seller JOIN ORDERS AS O ON O.ProductID=P.ProductID JOIN SEARCHES AS SE ON SE.IPAddress=O.IPAddress AND
SE.SearchDT=O.SearchDT JOIN BUYERS AS B ON B.Buyer=SE.Buyer 
WHERE YEAR(O.SearchDT)=2025 
ORDER BY  O.FinalPrice DESC

--מספר הפעמים שמוצר יצא בחיפוש ופרטי המוצר
SELECT P.ProductID, S.Seller, SE.Category, NumOfSearches= COUNT(*)
FROM SEARCHES AS SE JOIN RETRIEVES AS R ON R.SearchDT=SE.SearchDT AND R.IPAddress=SE.IPAddress JOIN PRODUCTS AS P ON P.ProductID=R.ProductID 
JOIN SELLERS AS S ON P.Seller = S.Seller
GROUP BY P.ProductID, SE.Category, S.Seller
ORDER BY  NumOfSearches DESC;


-- ==================== Nested queries ====================
----------------שאילתות מקוננות 
--השאילתה מחזירה הזמנות מ-2025 ומעלה עם מחיר גבוה מהממוצע וממיינת לפי מחיר יורד.
SELECT S.Buyer, O.ProductID, O.FinalPrice
FROM ORDERS AS O JOIN SEARCHES AS S ON O.IPAddress = S.IPAddress AND O.SearchDT = S.SearchDT
WHERE YEAR(O.SearchDT) >= 2025 AND
FinalPrice> (
SELECT AVG(FinalPrice)
FROM ORDERS
WHERE YEAR(O.SearchDT) >= 2025
)
ORDER BY FinalPrice DESC

--השאילתה מחשבת את סך ההכנסות ממוכרים שמכרו יותר מ-3 מוצרים. היא מסייעת בזיהוי מוכרים פעילים ותורמת לניתוח ההכנסות ממוכרים מובילים, לשיפור אסטרטגיות עסקיות
SELECT SUM(FinalPrice) AS TotalRevenue
FROM ORDERS                                                                                                        
WHERE Seller IN (
    SELECT Seller
    FROM ORDERS
    GROUP BY Seller
    HAVING COUNT(ProductID) > 3
);


-- ==================== Window functions ====================
------------------------------------------פונקציות חלון
--פרטים על מוכרים מבחינת הכנסות- הכנסהת הפער מההכנסה הגבוהה ביותר, מספר הזמנות ודירוג לפי מספר הזמנות 
SELECT  Seller, TotalIncome= SUM(FinalPrice), IncomeGap= MAX(SUM(FinalPrice)) OVER (PARTITION BY YEAR(SearchDT)) - SUM(FinalPrice), 
OrdersNum=count(*) , OrdersNumRank= RANK() OVER (PARTITION BY YEAR(SearchDT) ORDER BY count(*) desc)
FROM ORDERS
GROUP BY Seller, YEAR(SearchDT)
ORDER BY IncomeGap ASC, OrdersNumRank;

--מחשבת כמות חיפושים לכל קונה ופער מהממוצע ב-3 החודשים האחרונים.
SELECT DISTINCT B.Buyer AS Username,
COUNT(S.SearchDT) OVER (PARTITION BY B.Buyer) AS SearchCount,
COUNT(S.SearchDT) OVER (PARTITION BY B.Buyer)-(SELECT AVG(CountedSearches.AvgCount)
     FROM (
         SELECT COUNT(*) AS AvgCount
         FROM SEARCHES
         GROUP BY Buyer
     ) AS CountedSearches
    )  AS GAP
FROM SEARCHES AS S JOIN BUYERS AS B ON S.Buyer = B.Buyer
-- anchored on the latest search in the data (the sample data is static, so GETDATE() would return no rows)
WHERE S.SearchDT >= DATEADD(MONTH, -3, (SELECT MAX(SearchDT) FROM SEARCHES))
ORDER BY SearchCount DESC;


-- ==================== View: category performance ====================
------------------------VIEW 
--ניתוח לפי קטגוריה- חיפושים מול הזמנות ויחס
GO
DROP VIEW IF EXISTS CategorysDetails;
GO
CREATE VIEW CategorysDetails AS
SELECT 
    S.Category, TotalSearches=COUNT(distinct S.IPAddress), Orders=COUNT(distinct o.OrderNumber),Ratio = round(CAST(COUNT(DISTINCT  O.OrderNumber) AS FLOAT) / NULLIF(COUNT(DISTINCT S.IPAddress), 0),2)
	FROM CATEGORIES AS C JOIN SEARCHES AS S ON C.category=S.Category left join ORDERS AS O ON S.IPAddress = O.IPAddress AND S.SearchDT = O.SearchDT left join RETRIEVES as r  on S.IPAddress = r.IPAddress AND S.SearchDT = r.SearchDT
GROUP BY S.Category;
GO

select *
from CategorysDetails
ORDER BY TotalSearches desc


-- ==================== Scalar function: conversion rate ====================
--------------------------פונקציה סקלרית
--אחוז המרה של חיפושים להזמנות לפי קטגוריה
GO
DROP FUNCTION IF EXISTS ConversionRate;
GO
CREATE FUNCTION ConversionRate (@Category VARCHAR(50))
RETURNS float
AS
BEGIN
    DECLARE @Difference float;
   SELECT @Difference = ROUND((CAST(c.Orders AS FLOAT) / NULLIF(c.TotalSearches, 0)) * 100, 2)
    FROM CategorysDetails as c
    WHERE c.Category = @Category; 
    RETURN @Difference;
END;
GO

--בדיקה
SELECT Category, ConversionRate= dbo.ConversionRate(Category)
FROM CategorysDetails
order by ConversionRate desc


-- ==================== Table-valued function: most searched products ====================
--------------------פונקציה טבלה
--המוצרים הכי מחופשים לפי קטגוריה
GO
DROP FUNCTION IF EXISTS GetTopSearchedProductsByCategory;
GO
CREATE FUNCTION GetTopSearchedProductsByCategory (@Category VARCHAR(100))
RETURNS TABLE
AS
RETURN
(
    SELECT TOP 10 R.ProductID, COUNT(*) AS SearchCount
    FROM RETRIEVES AS R JOIN SEARCHES AS S ON R.IPAddress = S.IPAddress AND R.SearchDT = S.SearchDT
    WHERE S.Category = @Category
    GROUP BY R.ProductID
    ORDER BY SearchCount DESC
);
GO

SELECT *
FROM GetTopSearchedProductsByCategory('Accessories');


-- ==================== CTE: churn-risk classification ====================
--------------------------מקוננת WITH
-- מחשבת חיפושים בשבוע הראשון של ינואר 2025 לכל לקוח, כולל לקוחות שלא חיפשו 
WITH RecentSearchActivity AS (
    -- ספירת חיפושים של כל לקוח בשבוע הראשון של ינואר 2025
    SELECT s.Buyer, COUNT(*) AS SearchCount
    FROM SEARCHES s
    WHERE s.SearchDT >= '2025-01-01' AND s.SearchDT < '2025-01-08' -- the whole of Jan 1-7 (BETWEEN ... '2025-01-07' would drop everything after midnight on Jan 7)
    GROUP BY s.Buyer
),
AllCustomers AS (
    -- רשימת כל הלקוחות
    SELECT DISTINCT Buyer
    FROM SEARCHES
),
InactiveCustomers AS (
    -- לקוחות עם חיפושים שנמצאים או לא נמצאים בטבלת RecentSearchActivity
    SELECT
        ac.Buyer,
        CASE
            WHEN rsa.SearchCount IS NOT NULL THEN rsa.SearchCount
            ELSE 0
        END AS SearchCount
    FROM AllCustomers ac
    LEFT JOIN RecentSearchActivity rsa ON ac.Buyer = rsa.Buyer
)

-- לקוחות עם דירוג סיכון לנטישה
SELECT Buyer,
       SearchCount,
       CASE
           WHEN SearchCount = 0 THEN 'High Risk'
           WHEN SearchCount BETWEEN 1 AND 5 THEN 'Medium Risk'
           ELSE 'Low Risk'
       END AS RiskLevel
FROM InactiveCustomers
ORDER BY SearchCount ASC, RiskLevel DESC;


-- ==================== Stored procedure: users to notify ====================
-------------------------------פרוצדורה
--הפרוצדורה מזהה משתמשים שדורשים התראה על סמך פעילות נמוכה, מוצרים שלא נמכרו, Wishlist פעיל, או חוסר הזמנות, ושומרת אותם בטבלה זמנית לצורך שליחה.
GO
DROP PROCEDURE IF EXISTS NotifyUsersForEngagement;
GO
CREATE PROCEDURE NotifyUsersForEngagement(@DaysInactive INT)
AS
BEGIN
    -- Reference date = the latest search in the data (the sample data is static, so GETDATE() would mark every user inactive)
    DECLARE @Today DATETIME = (SELECT MAX(SearchDT) FROM SEARCHES);

    -- יצירת טבלה זמנית עבור התוצאות
    CREATE TABLE #UsersToNotify (
        Username NVARCHAR(20),
        MailAddress NVARCHAR(40),
        NotificationType NVARCHAR(50)
    );

    -- משתמשים עם מוצרים שעדיין לא נמכרו
    INSERT INTO #UsersToNotify (Username, MailAddress, NotificationType)
    SELECT DISTINCT u.Username, u.MailAddress, 'Unlisted Product Not Sold'
    FROM USERS u
    JOIN SELLERS s ON u.Username = s.Seller
    JOIN PRODUCTS p ON s.Seller = p.Seller
    WHERE NOT EXISTS (
        SELECT 1
        FROM ORDERS o
        WHERE o.ProductID = p.ProductID AND o.Seller = p.Seller
    );

    -- משתמשים עם מוצרים ב-Wishlist
    INSERT INTO #UsersToNotify (Username, MailAddress, NotificationType)
    SELECT DISTINCT u.Username, u.MailAddress, 'Wishlist Items'
    FROM USERS u
    JOIN WISHLIST wl ON u.Username = wl.Username;

    -- משתמשים שלא היו פעילים זמן ממושך (לא עשו חיפושים)
    INSERT INTO #UsersToNotify (Username, MailAddress, NotificationType)
    SELECT DISTINCT u.Username, u.MailAddress, 'Inactive User'
    FROM USERS u
    LEFT JOIN SEARCHES s ON u.Username = s.Buyer
    GROUP BY u.Username, u.MailAddress
    HAVING MAX(s.SearchDT) IS NULL OR DATEDIFF(DAY, MAX(s.SearchDT), @Today) > @DaysInactive;

    -- משתמשים שלא ביצעו אף הזמנה
    INSERT INTO #UsersToNotify (Username, MailAddress, NotificationType)
    SELECT DISTINCT u.Username, u.MailAddress, 'No Orders'
    FROM USERS u
    JOIN BUYERS b ON u.Username = b.Buyer
    WHERE NOT EXISTS (
        SELECT 1
        FROM SEARCHES s
        JOIN ORDERS o ON o.IPAddress = s.IPAddress AND o.SearchDT = s.SearchDT
        WHERE s.Buyer = u.Username
    );

    -- שליפת הנתונים מהטבלה הזמנית
    SELECT * FROM #UsersToNotify;

    -- ניקוי הטבלה הזמנית
    DROP TABLE #UsersToNotify;
END;
GO

--שורה לבדיקת הפרוצדורה עם קלט של 3 ימים
EXEC NotifyUsersForEngagement @DaysInactive = 3;


-- ==================== Trigger: remove purchased items from the wishlist (with test) ====================
--------------------------------------------------------------טריגר
  -- מחיקת מוצרים מרשימת המשאלות כאשר המשתמש רכש אותם
DROP TRIGGER IF EXISTS RemoveFromWishlist;
GO
GO
CREATE TRIGGER RemoveFromWishlist
ON ORDERS
AFTER INSERT
AS
BEGIN
    DELETE FROM WISHLIST
    WHERE EXISTS (
        SELECT 1
        FROM INSERTED AS I
        JOIN SEARCHES AS S
            ON S.IPAddress = I.IPAddress
            AND S.SearchDT = I.SearchDT
        WHERE WISHLIST.ProductID = I.ProductID
          AND WISHLIST.Seller = I.Seller
          AND WISHLIST.Username = S.Buyer
    );
END;
GO

SELECT * 
FROM WISHLIST
WHERE Username = 'user1' AND Seller = 'seller1' AND ProductID = 101;

INSERT INTO USERS (Username, UserPassword, MailAddress, PhoneNumber)
VALUES
('user1', 'password123', 'user1@example.com', '0501234567'),
('seller1', 'password456', 'seller1@example.com', '0507654321');

INSERT INTO BUYERS (Buyer)
VALUES
('user1');

INSERT INTO SELLERS (Seller)
VALUES
('seller1');

INSERT INTO SEARCHES (IPAddress, SearchDT, Keywords, Category, Buyer)
VALUES
('192.168.1.1', '2025-01-01 12:00:00', 'keyword', 'Shoes', 'user1');

INSERT INTO PRODUCTS (Seller, ProductID, Size, Price, Brand, Color, ProductDescription)
VALUES
('seller1', 101, 'M', 100.00, 'BrandX', 'Red', 'Product Description');

INSERT INTO WISHLIST ( Username, Seller, ProductID, AddDT)
VALUES
('user1', 'seller1', 101, '2025-01-02 12:00:00');


--בדיקה 
SELECT * 
FROM WISHLIST
WHERE Username = 'user1' AND Seller = 'seller1' AND ProductID = 101;

INSERT INTO ORDERS (OrderNumber, City, Seller, ProductID, IPAddress, SearchDT, CCAccount, ZipCode, FinalPrice)
VALUES
(1, 'CityX', 'seller1', 101, '192.168.1.1', '2025-01-01 12:00:00', '0000000000000000', '12345678', 100.00);

--בדיקה שהוא הוסר
 SELECT * 
 FROM WISHLIST
WHERE Username = 'user1' AND Seller = 'seller1' AND ProductID = 101;


DELETE FROM ORDERS WHERE OrderNumber = 1;

-- מחיקת הנתון מ-WISHLIST
DELETE FROM WISHLIST WHERE Username = 'user1' AND Seller = 'seller1' AND ProductID = 101;

-- מחיקת הנתון מ-SEARCHES
DELETE FROM SEARCHES WHERE IPAddress = '192.168.1.1' AND SearchDT = '2025-01-01 12:00:00';

-- מחיקת הנתון מ-PRODUCTS
DELETE FROM PRODUCTS WHERE Seller = 'seller1' AND ProductID = 101;

-- מחיקת הנתון מ-BUYERS
DELETE FROM BUYERS WHERE Buyer = 'user1';

-- מחיקת הנתון מ-SELLERS
DELETE FROM SELLERS WHERE Seller = 'seller1';

-- מחיקת הנתון מ-USERS
DELETE FROM USERS WHERE Username IN ('user1', 'seller1');

 SELECT * 
 FROM WISHLIST
WHERE Username = 'user1' AND Seller = 'seller1' AND ProductID = 101;


-- ==================== Query optimization: indexes and a rewritten query ====================
--------------------------------אינדקסים
--שאילתה שכבר כתבנו למעלה
SELECT S.Buyer, O.ProductID, O.FinalPrice
FROM ORDERS AS O JOIN SEARCHES AS S ON O.IPAddress = S.IPAddress AND O.SearchDT = S.SearchDT
WHERE YEAR(O.SearchDT) >= 2025 AND
FinalPrice> (
SELECT AVG(FinalPrice)
FROM ORDERS
WHERE YEAR(O.SearchDT) >= 2025
)
ORDER BY FinalPrice DESC

--השאילתה מוצאת הזמנות מ-2025 שמחירן מעל הממוצע, וממיינת אותן בסדר יורד לפי המחיר- אינדקסים
DROP INDEX IF EXISTS IDX_Orders_SearchDT_FinalPrice_IPAddress ON ORDERS;
CREATE INDEX IDX_Orders_SearchDT_FinalPrice_IPAddress ON ORDERS(SearchDT, FinalPrice, IPAddress);
DROP INDEX IF EXISTS IDX_Searches_IPAddress_SearchDT_Buyer ON SEARCHES;
CREATE INDEX IDX_Searches_IPAddress_SearchDT_Buyer ON SEARCHES(IPAddress, SearchDT, Buyer);

WITH AvgFinalPrice AS (
    SELECT AVG(FinalPrice) AS AvgPrice
    FROM ORDERS
    WHERE YEAR(SearchDT) >= 2025
)
SELECT S.Buyer, O.ProductID, O.FinalPrice
FROM ORDERS AS O
JOIN SEARCHES AS S ON O.IPAddress = S.IPAddress AND O.SearchDT = S.SearchDT
CROSS JOIN AvgFinalPrice AFP
WHERE YEAR(O.SearchDT) >= 2025
  AND O.FinalPrice > AFP.AvgPrice
ORDER BY O.FinalPrice DESC;

--שאילתה שכבר כתבנו למעלה
SELECT P.ProductID, S.Seller, SE.Category, NumOfSearches= COUNT(*)
FROM SEARCHES AS SE 
JOIN RETRIEVES AS R ON R.SearchDT=SE.SearchDT AND R.IPAddress=SE.IPAddress 
JOIN PRODUCTS AS P ON P.ProductID=R.ProductID
JOIN SELLERS AS S ON P.Seller = S.Seller
GROUP BY P.ProductID, SE.Category, S.Seller
ORDER BY  NumOfSearches DESC;

--השאילתה מחזירה את כמות החיפושים לפי מוצר, מוכר וקטגוריה, ממיינת את התוצאות לפי כמות החיפושים בסדר יורד אינדקסים
DROP INDEX IF EXISTS IDX_Searches_SearchDT_IPAddress ON SEARCHES;
CREATE INDEX IDX_Searches_SearchDT_IPAddress ON SEARCHES(SearchDT, IPAddress);
DROP INDEX IF EXISTS IDX_Retrieves_SearchDT_IPAddress_ProductID ON RETRIEVES;
CREATE INDEX IDX_Retrieves_SearchDT_IPAddress_ProductID ON RETRIEVES(SearchDT, IPAddress, ProductID);
DROP INDEX IF EXISTS IDX_Products_ProductID_Seller ON PRODUCTS;
CREATE INDEX IDX_Products_ProductID_Seller ON PRODUCTS(ProductID, Seller);
DROP INDEX IF EXISTS IDX_Sellers_Seller ON SELLERS;
CREATE INDEX IDX_Sellers_Seller ON SELLERS(Seller);

SELECT P.ProductID, S.Seller, SE.Category, COUNT(*) AS NumOfSearches
FROM SEARCHES AS SE 
JOIN RETRIEVES AS R ON R.SearchDT = SE.SearchDT AND R.IPAddress = SE.IPAddress
JOIN PRODUCTS AS P ON P.ProductID = R.ProductID
JOIN SELLERS AS S ON P.Seller = S.Seller
GROUP BY P.ProductID, S.Seller, SE.Category
ORDER BY COUNT(*) DESC;


-- ==================== Views built for the Power BI dashboards ====================
-----------------------------תוספות בשביל הלוח מחוונים
--רווח לפי שעה ביום


--רווח ממוצע לפי יום בשבוע
GO
DROP VIEW IF EXISTS WeeklyKeywordCategoryAverage;
GO
CREATE VIEW WeeklyKeywordCategoryAverage AS
SELECT
    DailySearches.DayOfWeek, -- יום בשבוע
    DailySearches.Keyword, -- מילת חיפוש
    DailySearches.Category, -- קטגוריה
    AVG(DailySearches.TotalSearches) AS AverageSearches -- ממוצע החיפושים
FROM
    (
        SELECT
            CONVERT(DATE, SearchDT) AS SearchDate, -- תאריך החיפוש
            DATENAME(WEEKDAY, SearchDT) AS DayOfWeek, -- יום בשבוע
            Keywords AS Keyword, -- מילת חיפוש
            Category, -- קטגוריה
            COUNT(*) AS TotalSearches -- מספר החיפושים לאותו יום וקטגוריה
        FROM
            SEARCHES -- טבלת המקור
        GROUP BY
            CONVERT(DATE, SearchDT),
            DATENAME(WEEKDAY, SearchDT),
            Keywords,
            Category
    ) AS DailySearches
GROUP BY
    DailySearches.DayOfWeek,
    DailySearches.Keyword,
    DailySearches.Category;
GO


		select *
	from WeeklyKeywordCategoryAverage


--ממוצע חיפושים לפי מילת חיפוש בכל ארבע שעות
GO
DROP VIEW IF EXISTS SearchesBy4HourAndKeywordCategoryAvg;
GO
CREATE VIEW SearchesBy4HourAndKeywordCategoryAvg AS
SELECT
    CASE
        WHEN DATEPART(HOUR, s.SearchDT) BETWEEN 0 AND 3 THEN '00:00-03:59'
        WHEN DATEPART(HOUR, s.SearchDT) BETWEEN 4 AND 7 THEN '04:00-07:59'
        WHEN DATEPART(HOUR, s.SearchDT) BETWEEN 8 AND 11 THEN '08:00-11:59'
        WHEN DATEPART(HOUR, s.SearchDT) BETWEEN 12 AND 15 THEN '12:00-15:59'
        WHEN DATEPART(HOUR, s.SearchDT) BETWEEN 16 AND 19 THEN '16:00-19:59'
        WHEN DATEPART(HOUR, s.SearchDT) BETWEEN 20 AND 23 THEN '20:00-23:59'
    END AS TimeSlot, -- חלון השעות
    s.Keywords AS Keyword, -- מילת חיפוש
    s.Category, -- קטגוריית החיפוש
    CAST(AVG(COUNT(*)) OVER (PARTITION BY
        CASE
            WHEN DATEPART(HOUR, s.SearchDT) BETWEEN 0 AND 3 THEN '00:00-03:59'
            WHEN DATEPART(HOUR, s.SearchDT) BETWEEN 4 AND 7 THEN '04:00-07:59'
            WHEN DATEPART(HOUR, s.SearchDT) BETWEEN 8 AND 11 THEN '08:00-11:59'
            WHEN DATEPART(HOUR, s.SearchDT) BETWEEN 12 AND 15 THEN '12:00-15:59'
            WHEN DATEPART(HOUR, s.SearchDT) BETWEEN 16 AND 19 THEN '16:00-19:59'
            WHEN DATEPART(HOUR, s.SearchDT) BETWEEN 20 AND 23 THEN '20:00-23:59'
        END,
        s.Keywords,
        s.Category
    ) AS DECIMAL(10, 2)) AS AverageSearches -- ממוצע חיפושים
FROM
    SEARCHES s
GROUP BY
    CASE
        WHEN DATEPART(HOUR, s.SearchDT) BETWEEN 0 AND 3 THEN '00:00-03:59'
        WHEN DATEPART(HOUR, s.SearchDT) BETWEEN 4 AND 7 THEN '04:00-07:59'
        WHEN DATEPART(HOUR, s.SearchDT) BETWEEN 8 AND 11 THEN '08:00-11:59'
        WHEN DATEPART(HOUR, s.SearchDT) BETWEEN 12 AND 15 THEN '12:00-15:59'
        WHEN DATEPART(HOUR, s.SearchDT) BETWEEN 16 AND 19 THEN '16:00-19:59'
        WHEN DATEPART(HOUR, s.SearchDT) BETWEEN 20 AND 23 THEN '20:00-23:59'
    END,
    s.Keywords,
    s.Category;
GO

	select *
	from SearchesBy4HourAndKeywordCategoryAvg


--סך ההכנסות מכל עיר ומספר ההזמנות
GO
DROP VIEW IF EXISTS RevenueByRegion;
GO
CREATE VIEW RevenueByRegion AS
SELECT 
    o.City AS Region,
    SUM(o.FinalPrice) AS TotalRevenue,
    COUNT(*) AS TotalOrders,
    COUNT(DISTINCT s.Buyer) AS TotalCustomers
FROM 
    ORDERS o
JOIN 
    SEARCHES s ON o.IPAddress = s.IPAddress AND o.SearchDT = s.SearchDT
GROUP BY 
    o.City;
GO

-- בדיקה
SELECT *
FROM RevenueByRegion
ORDER BY TotalRevenue DESC;

--רווחים על פי מילת מפתח וקטגוריה
GO
DROP VIEW IF EXISTS KeywordAndCategoryRevenueAnalysis;
GO
CREATE VIEW KeywordAndCategoryRevenueAnalysis AS
SELECT 
    S.Keywords AS Keyword,
    S.Category AS Category,
    SUM(O.FinalPrice) AS TotalRevenue,
    SUM(P.Price) AS TotalOriginalPrices,
    SUM(O.FinalPrice) - SUM(P.Price) AS RevenueDifference,
    ROUND(AVG((P.Price - O.FinalPrice) / P.Price * 100), 2) AS AverageDiscountPercentage
FROM 
    ORDERS AS O
JOIN 
    PRODUCTS AS P ON O.ProductID = P.ProductID
JOIN 
    SEARCHES AS S ON O.IPAddress = S.IPAddress AND O.SearchDT = S.SearchDT
GROUP BY 
    S.Keywords, S.Category;
GO

-- בדיקת ה-View
SELECT *
FROM KeywordAndCategoryRevenueAnalysis
ORDER BY TotalRevenue DESC;

--הזמנה אחרונה של לקוח
GO
DROP VIEW IF EXISTS CustomerLastOrder;
GO
CREATE VIEW CustomerLastOrder AS
SELECT 
    S.Buyer AS CustomerName,
    MAX(O.SearchDT) AS LastOrderDate,
    (
        SELECT TOP 1 O2.City
        FROM ORDERS AS O2
        JOIN SEARCHES AS S2 ON O2.IPAddress = S2.IPAddress AND O2.SearchDT = S2.SearchDT
        WHERE S2.Buyer = S.Buyer
        ORDER BY O2.SearchDT DESC
    ) AS City
FROM 
    ORDERS AS O
JOIN 
    SEARCHES AS S ON O.IPAddress = S.IPAddress AND O.SearchDT = S.SearchDT
GROUP BY 
    S.Buyer;
GO

	SELECT *
FROM CustomerLastOrder


--חיפושים לפי מילת מפתח וקטגוריה בשביל סינון
GO
DROP VIEW IF EXISTS SearchesAndOrdersByKeywordAndCategory;
GO
CREATE VIEW SearchesAndOrdersByKeywordAndCategory AS
SELECT
    s.Keywords AS Keyword, 
    s.Category AS Category, 
    COUNT(s.SearchDT) AS TotalSearches, 
    COUNT(o.OrderNumber) AS TotalOrders 
FROM
    SEARCHES s
LEFT JOIN
    ORDERS o ON s.IPAddress = o.IPAddress AND s.SearchDT = o.SearchDT -- חיבור חיפושים להזמנות
GROUP BY
    s.Keywords,
    s.Category;
GO


	select *
	from SearchesAndOrdersByKeywordAndCategory

------------------------------------------------------ תוספות בשביל הדוח
--חיפושים והזמניות ליום בקטגוריה
GO
DROP VIEW IF EXISTS CategoryAndDailySummary;
GO
	CREATE VIEW CategoryAndDailySummary AS
SELECT 
    DATENAME(WEEKDAY, s.SearchDT) AS SearchDay, -- שם היום
    s.Category, -- קטגוריה
    COUNT(s.IPAddress) AS TotalSearches, -- סך החיפושים
    COUNT(o.OrderNumber) AS TotalOrders, -- סך ההזמנות
    (CAST(COUNT(o.OrderNumber) AS FLOAT) / NULLIF(COUNT(s.IPAddress), 0)) * 100 AS ConversionRate -- אחוזי המרה
FROM Searches as s LEFT JOIN Orders o
ON s.IPAddress = o.IPAddress AND s.SearchDT = o.SearchDT
GROUP BY DATENAME(WEEKDAY, s.SearchDT), s.Category;
GO


	SELECT *
FROM CategoryAndDailySummary

--סך חיפושים לפי שעה ויום
GO
DROP VIEW IF EXISTS HourlyAndDailySearches;
GO
CREATE VIEW HourlyAndDailySearches AS
SELECT
DATEPART(HOUR, SearchDT) AS SearchHour,
DATENAME(WEEKDAY, SearchDT) AS SearchDay,
COUNT(*) AS TotalSearches
FROM Searches
GROUP BY DATEPART(HOUR, SearchDT), DATENAME(WEEKDAY, SearchDT);
GO

	SELECT *
FROM HourlyAndDailySearches

--צירת טבלת Lookup עבור ימים בשבוע:
GO
DROP VIEW IF EXISTS LookupDays;
GO
CREATE VIEW LookupDays AS
SELECT DISTINCT SearchDay
FROM CategoryAndDailySummary
UNION
SELECT DISTINCT SearchDay
FROM HourlyAndDailySearches;
GO

--מטרת ה-VIEW מעקב אחרי ביצועי קטגוריות- להבין אילו קטגוריות מקבלות הכי הרבה חיפושים והזמנות.
GO
DROP VIEW IF EXISTS CategoryConversion;
GO
CREATE VIEW CategoryConversion AS
SELECT 
    s.Category,
    COUNT(s.IPAddress) AS TotalSearches,
    COUNT(o.OrderNumber) AS TotalOrders,
    (CAST(COUNT(o.OrderNumber) AS FLOAT) / NULLIF(COUNT(s.IPAddress), 0)) * 100 AS ConversionRate
FROM Searches s
LEFT JOIN Orders o
ON s.IPAddress = o.IPAddress AND s.SearchDT = o.SearchDT
GROUP BY s.Category;
GO

	SELECT *
FROM CategoryConversion

--ה-VIEW HOURSEARCHES3 נועד להחזיר את שלוש השעות החלשות ביותר מבחינת מספר החיפושים בטווח שעות מסוים (6 בבוקר עד 2 בלילה).
GO
DROP VIEW IF EXISTS HOURSEARCHES3;
GO
CREATE VIEW HOURSEARCHES3 AS
SELECT TOP 3 
    DATEPART(HOUR, SearchDT) AS SEARCHHOUR, 
    COUNT(*) AS TOTALSEARCHES
FROM SEARCHES AS S
WHERE (DATEPART(HOUR, SearchDT) >= 6 AND DATEPART(HOUR, SearchDT) <= 23) -- שעות בין 6 בבוקר לחצות
    OR (DATEPART(HOUR, SearchDT) >= 0 AND DATEPART(HOUR, SearchDT) <= 2) -- שעות בין חצות ל-2 בלילה
GROUP BY  DATEPART(HOUR, SearchDT)
ORDER BY TOTALSEARCHES ASC;
GO

	SELECT *
FROM HOURSEARCHES3

--ה-VIEW WEEKDAYSEARCHES2 מחזיר את שלושת הימים החלשים ביותר בשבוע מבחינת מספר החיפושים.
GO
DROP VIEW IF EXISTS WEEKDAYSEARCHES2;
GO
CREATE VIEW WEEKDAYSEARCHES2 AS(
SELECT TOP 3 DATENAME(WEEKDAY, SearchDT) AS SEARCHDAY, COUNT (*) AS TOTALSEARCHES
FROM SEARCHES AS S
GROUP BY DATENAME(WEEKDAY, SearchDT)
ORDER BY TOTALSEARCHES ASC
)
GO

	SELECT *
FROM WEEKDAYSEARCHES2
