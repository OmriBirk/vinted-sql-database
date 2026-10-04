-- Vinted-style marketplace database (SQL Server / T-SQL)
-- 14 tables with primary/foreign keys, CHECK and UNIQUE constraints, plus lookup tables.
-- Re-runnable: drops and recreates everything. Requires SQL Server 2016 or later.

IF DB_ID(N'VintedDB') IS NULL CREATE DATABASE VintedDB;
GO
USE VintedDB;
GO

-- Drop in dependency order so the script can be re-run
DROP TABLE IF EXISTS ORDERS, RETRIEVES, WISHLIST, REVIEWSLIST, CHATS, CREDITCARDS,
                     PRODUCTS, SEARCHES, BUYERS, SELLERS, USERS, COLORS, RANKS, CATEGORIES;
GO

CREATE TABLE USERS(
    Username VARCHAR(20) PRIMARY KEY NOT NULL, 
    UserPassword VARCHAR(40) NOT NULL, 
    MailAddress VARCHAR(40) NOT NULL, 
    PhoneNumber VARCHAR(10) NOT NULL,
    CONSTRAINT CK_Username CHECK (LEN(Username) BETWEEN 3 AND 20),
    CONSTRAINT CK_MailAdress CHECK (MailAddress LIKE '%@%.%'),
    CONSTRAINT AK_MailAdress UNIQUE (MailAddress),
    CONSTRAINT CK_PhoneNumber CHECK (PhoneNumber LIKE '05[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]'),
    CONSTRAINT AK_PhoneNumber UNIQUE (PhoneNumber),
    CONSTRAINT CK_Password CHECK (LEN(UserPassword) > 7)
);

CREATE TABLE BUYERS( 
    Buyer VARCHAR(20) PRIMARY KEY NOT NULL,
    CONSTRAINT FK_Buyer FOREIGN KEY (Buyer) REFERENCES USERS(Username),
    CONSTRAINT CK_Buyer CHECK (LEN(Buyer) BETWEEN 3 AND 20)
);

CREATE TABLE SELLERS( 
    Seller VARCHAR(20) PRIMARY KEY NOT NULL,
    CONSTRAINT FK_Seller FOREIGN KEY (Seller) REFERENCES USERS(Username),
    CONSTRAINT CK_Seller CHECK (LEN(Seller) BETWEEN 3 AND 20)
);

CREATE TABLE CHATS(
    Seller VARCHAR(20) NOT NULL, 
    Buyer VARCHAR(20) NOT NULL,
    CONSTRAINT PK_Chats PRIMARY KEY (Seller, Buyer),
    CONSTRAINT FK_BuyerChats FOREIGN KEY (Buyer) REFERENCES BUYERS(Buyer),
    CONSTRAINT FK_SellerChats FOREIGN KEY (Seller) REFERENCES SELLERS(Seller)
);

CREATE TABLE SEARCHES(
    IPAddress VARCHAR(40) NOT NULL, 
    SearchDT DATETIME NOT NULL, 
    Keywords VARCHAR(40), 
    Category VARCHAR(50), 
    Buyer VARCHAR(20),
    CONSTRAINT PK_Searches PRIMARY KEY (IPAddress, SearchDT),
    CONSTRAINT FK_BuyerSearches FOREIGN KEY (Buyer) REFERENCES BUYERS(Buyer),
    CONSTRAINT CK_Search_DT CHECK (SearchDT <= GETDATE())
);

CREATE TABLE CREDITCARDS(
    CCAccount CHAR(16) PRIMARY KEY NOT NULL, 
    CCtype VARCHAR(10), 
    CCexpiration CHAR(5), 
    Buyer VARCHAR(20),
    CONSTRAINT FK_BuyerCreditCards FOREIGN KEY (Buyer) REFERENCES BUYERS(Buyer)
);

CREATE TABLE PRODUCTS(
    Seller VARCHAR(20), 
    ProductID BIGINT, 
    Size VARCHAR(10), 
    Price money, 
    Brand VARCHAR(40), 
    Color VARCHAR(10), 
    ProductDescription VARCHAR(100), 
    CONSTRAINT PK_Products PRIMARY KEY (Seller, ProductID),
    CONSTRAINT FK_SellerProducts FOREIGN KEY (Seller) REFERENCES SELLERS(Seller),
    CONSTRAINT CK_ProductID CHECK (ProductID > 0),
    CONSTRAINT CK_Price CHECK (Price > 0)
);

CREATE TABLE RETRIEVES(
    Seller VARCHAR(20), 
    ProductID BIGINT, 
	IPAddress VARCHAR(40), 
    SearchDT DATETIME,
	CONSTRAINT PK_RETRIEVES PRIMARY KEY (Seller, ProductID, IPAddress, SearchDT),
	CONSTRAINT FK_Products FOREIGN KEY (Seller, ProductID) REFERENCES PRODUCTS(Seller, ProductID),
	CONSTRAINT FK_IPAddress FOREIGN KEY (IPAddress, SearchDT) REFERENCES SEARCHES(IPAddress, SearchDT)
);

CREATE TABLE WISHLIST(
    Username VARCHAR(20) NOT NULL,
    Seller VARCHAR(20) NOT NULL,
    ProductID BIGINT NOT NULL,
AddDT DATETIME NOT NULL,
    CONSTRAINT PK_ProductsWISHLIST PRIMARY KEY (Username, Seller, ProductID),
    CONSTRAINT FK_UsernameWishList FOREIGN KEY (Username) REFERENCES USERS(Username),
    CONSTRAINT FK_ProductIDWishList FOREIGN KEY (Seller, ProductID) REFERENCES PRODUCTS(Seller, ProductID)
);

CREATE TABLE REVIEWSLIST(
    UsernameA VARCHAR(20),
    ReviewDT DATETIME, 
    ReviewDescription VARCHAR(100),
    ReviewRank CHAR(1),
	UsernameB VARCHAR(20),
    CONSTRAINT PK_ReviewsList PRIMARY KEY (UsernameA, ReviewDT),
    CONSTRAINT FK_UsernameReviewsListA FOREIGN KEY (UsernameA) REFERENCES USERS(Username),
    CONSTRAINT CK_ReviewDT CHECK (ReviewDT <= GETDATE()),
    CONSTRAINT CK_ReviewRank CHECK (ReviewRank IN ('1', '2', '3', '4', '5')),
	CONSTRAINT FK_UsernameReviewsListB FOREIGN KEY (UsernameB) REFERENCES USERS(Username)
);

CREATE TABLE ORDERS(
    OrderNumber BIGINT PRIMARY KEY NOT NULL, 
    City VARCHAR(40), 
    Seller VARCHAR(20), 
    ProductID BIGINT,
    IPAddress VARCHAR(40), 
    SearchDT DATETIME, 
    CCAccount CHAR(16),
    ZipCode VARCHAR(8),
	FinalPrice Money,
    CONSTRAINT FK_UsernameOrders FOREIGN KEY (Seller, ProductID) REFERENCES PRODUCTS(Seller, ProductID),
    CONSTRAINT FK_SearchOrders FOREIGN KEY (IPAddress, SearchDT) REFERENCES SEARCHES(IPAddress, SearchDT),
    CONSTRAINT CK_OrderNumber CHECK (OrderNumber > 0),
    CONSTRAINT CK_ZipCode CHECK (ZipCode LIKE '[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]'),
    CONSTRAINT CK_Address CHECK (LEN(City) BETWEEN 3 AND 20),
	CONSTRAINT CK_FinalPrice CHECK (FinalPrice>0)
);

CREATE TABLE COLORS (
    Color VARCHAR(10) PRIMARY KEY NOT NULL
);

INSERT INTO COLORS VALUES
('Yellow'), ('Orange'), ('White'), ('Black'), ('Green'), ('Blue'), ('Pink'), ('Purple'), ('Gray'), ('Red'), ('Brown'), ('Multicolor');

ALTER TABLE PRODUCTS
ADD CONSTRAINT FK_Color FOREIGN KEY (Color) REFERENCES COLORS (Color);

CREATE TABLE RANKS (
    ReviewRank CHAR(1) PRIMARY KEY NOT NULL
);

INSERT INTO RANKS VALUES
('1'), ('2'), ('3'), ('4'), ('5');

ALTER TABLE REVIEWSLIST
ADD CONSTRAINT FK_Rank FOREIGN KEY (ReviewRank) REFERENCES RANKS (ReviewRank);

CREATE TABLE CATEGORIES (
    category VARCHAR(50) PRIMARY KEY NOT NULL
);

INSERT INTO CATEGORIES VALUES
('Accessories'), ('Baby & Kids'), ('Clothing'), ('Home & Living'), ('Shoes'), ('Vintage'),('Sports Equipment');

ALTER TABLE SEARCHES
ADD CONSTRAINT FK_category FOREIGN KEY (category) REFERENCES CATEGORIES (category);
GO
