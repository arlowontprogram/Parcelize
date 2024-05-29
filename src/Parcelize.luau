--[[

	Title: Parcelize
	Date: 29/05/2024
	Created by: 110029109
	Version: 1.0.0

	--

	Description:
		This module aims to provide an open-source, maintained and structured
		module to allow easy integration with the Parcel API (v1)


	Token Setup:
		If you wish to use Roblox Secret keys,
		create a new entry for your game under the name of "ParcelToken"

		When initialising this module, you can either enter your token manually,
		or leave it blank and it will automatically fetch your secret key from Roblox.

	--

	Simplified API Overview:
		# Types overview
		<Packables> = {
			Delivery: {string},
			DisplayRobux: boolean,
			IsUSDOnsale: boolean,
			USDPrice: number?,
			Stripe: {}
		}

		<Product> = {
			Category: string,
			DecalId: number,
			Description: string,
			DeveloperProductId: number,
			Name: string,
			ProductId: ProductId,
			Stock: boolean | number,
			Tags: {string?},
			Packables: Packables?
		}

		# <ParcelInstance> Instance
		ParcelInstance:FetchHubInfo() -> { TotalSales: number, MusicId: number? }?
		ParcelInstance:FetchHubDescription() -> { LongDescription: string, ShortDescription: string }?
		ParcelInstance:FetchHubTerms() ->  { Terms: string? }?
		ParcelInstance:FetchBestseller() ->  { HubId: string, Product: <Product> }?
		ParcelInstance:FetchProducts() -> { HubId: string, Products: { <Product> } }?
		ParcelInstance:FetchPlayerOwnedProducts() -> { <Product> }?
		ParcelInstance:FetchPlayerProfile() -> { DiscordId: string, IsVerified: boolean, RobloxId: number, DiscordTag: string }
		ParcelInstance:Whitelist() -> ( boolean, { message: string, status: string }? )

		# ParcelAPI Instance
		ParcelAPI(AuthToken: string?, ForceDebugging: boolean?) -> <ParcelInstance>

	--

	API:
		ParcelAPI(AuthToken: string?, ForceDebugging: boolean?) -> <ParcelInstance>
		- Initialises a new ParcelInstance given an AuthToken, or fetched from Roblox.
		  As well, allowing forced debugging, regardless of instance runtime.

		```lua
		local ParcelAPI = require(<path>)
		local AuthToken = "eyJhbGciOiJIUzI1N..."

		local ParcelInstance = ParcelAPI(AuthToken)
		```

		-

		ParcelInstance:FetchHubInfo() -> { TotalSales: number, MusicId: number? }?
		- Fetches the Hub's current information, such as total sales and music playing

		```lua
		local HubInfo = ParcelInstance:FetchHubInfo()
		print(HubInfo.TotalSales)
		```

		-

		ParcelInstance:FetchHubDescription() -> { LongDescription: string, ShortDescription: string }?
		- Fetches two variations of the desired hub's descriptions, both a Long and a Short variation

		```lua
		local HubDescription = ParcelInstance:FetchHubDescription()
		print(HubDescription.LongDescription)
		```

		-

		ParcelInstance:FetchHubTerms() ->  { Terms: string? }?
		- Fetches the Hub's current terms and conditions, if they have any

		```lua
		local HubTerms = ParcelInstance:FetchHubTerms()
		print(HubTerms.Terms)
		```

		-

		ParcelInstance:FetchBestseller() ->  { HubId: string, Product: <Product> }?
		- Fetches the current bestseller on the desired hub, along with the product information

		```lua
		local Bestseller = ParcelInstance:FetchBestseller()
		print(Bestseller.Product.Name)
		```

		-

		ParcelInstance:FetchProducts( GetBestseller: boolean? = false ) -> { HubId: string, Products: { <Product> } }?
		- Fetches all the products on the desired hub, along with their product information
		  If `GetBestseller` is passed as `true`, the bestseller will be fetched instead

		```lua
		local Products = ParcelInstance:FetchProducts()
		for _, Product in pairs(Products.Products) do
			print(Product.Name)
		end
		```

		-

		ParcelInstance:FetchPlayerOwnedProducts( UserId: RobloxId ) -> { <Product> }?
		- Fetches all the products that the desired player owns on the desired hub, along with their product information

		```lua
		local UserId = 110029109
		local OwnedProducts = ParcelInstance:FetchPlayerOwnedProducts(UserId)
		for _, Product in pairs(OwnedProducts) do
			print(Product.Name) -- Luxury BMW M Series
		end
		```

		-

		ParcelInstance:FetchPlayerProfile( UserId: RobloxId | DiscordId, ProvidedUserType: UserType )
			-> { DiscordId: string, IsVerified: boolean, RobloxId: number, DiscordTag: string }
		- Fetches the player's profile, whether or not they are verified, and their DiscordId, if they have verified with Parcel
		- Requires the player's UserId, along with their UserType, whether or not they are a RobloxId or a DiscordId
		- Returns a table with the player's information, such as their DiscordId, RobloxId, and whether or not they are verifie

		```lua
		local UserId = 110029109
		local PlayerProfile = ParcelInstance:FetchPlayerProfile(UserId, "roblox")
		print(PlayerProfile.DiscordId)
		```

		-

		ParcelInstance:Whitelist(UserId: RobloxId, ProductId: ProductId) -> ( boolean, { message: string, status: string }? )
		- Whitelists the player to the desired product, given their RobloxId and the ProductId
		- Returns a tuple, with the first value being a boolean, whether or not the request was successful
		- Followed by table, which will be returned with two string keys: `message` and `status`

		```lua
		local WasSuccessful, Response = ParcelInstance:Whitelist()

		if WasSuccessful then
			print("Successfully whitelisted!")
		else
			warn("Failed to whitelist:", Response.message)
		end
		```

]]

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local ParcelAPI = {}
ParcelAPI.__index = ParcelAPI

-- Constants
local ParcelEndpoint = "api.parcelroblox.com/api"
local PaymentsEndpoint = "payments.parcelroblox.com/external"

-- Types
export type RobloxId = number
export type RobloxType = "roblox"

export type DiscordId = string
export type DiscordType = "discord"

export type UserType = (RobloxType | DiscordType)

export type ProductId = string

export type Packables = {
	Delivery: {string},
	DisplayRobux: boolean,
	IsUSDOnsale: boolean,
	USDPrice: number?,
	Stripe: {}
}

export type Product = {
	Category: string,
	DecalId: number,
	Description: string,
	DeveloperProductId: number,
	Name: string,
	ProductId: ProductId,
	Stock: boolean | number,
	Tags: {string?},
	Packables: Packables?
}

-- Internal
function ParcelAPI:_Debug( ... )
	if not self.Debugging then
		return
	end

	print("[ParcelAPI]:", ... )
end

function ParcelAPI:_IntegrityCheck()
	assert(self.AuthToken, "[ParcelAPI]: No AuthToken initialised!")
	assert(HttpService.HttpEnabled, "[ParcelAPI]: HTTP requests are not enabled!")

	-- also a cheeky caching opportunity
	local Data = self:FetchHubInfo()
	assert(Data, `[ParcelAPI]: Failed to initialise a new ParcelInstance: {Data}`)
end

function ParcelAPI:_Request(
	Path: string,
	Method: string?,
	Body: any?,
	IsPaymentsEndpointRelated: boolean?
): (boolean, any)
	local RequestOK, Response = pcall(HttpService.RequestAsync, HttpService, {
		Url = `https://{IsPaymentsEndpointRelated and PaymentsEndpoint or ParcelEndpoint}/{Path}`,
		Method = Method or "GET",
		Body = (Body ~= nil) and HttpService:JSONEncode(Body) or nil,		
		Headers = {
			["Content-Type"] = "application/json",
			["hub-secret-key"] = self.AuthToken,
		}
	})

	if not RequestOK then
		warn(`[ParcelAPI]: {
			RequestOK and "Successfully" or "Failed to"
			} {Method} {Path}: {Response.StatusCode}, {Response.StatusMessage}`)
	end

	local ParsedJSON, ParsedBody = pcall(HttpService.JSONDecode, HttpService, Response.Body)

	if not ParsedJSON then
		warn(`[ParcelAPI]: Failed to parse JSON for {Path}: {ParsedBody}`, Response.Body)
	end

	return RequestOK, if ParsedJSON then ParsedBody
		else Response.StatusMessage
end

function ParcelAPI:_ShouldReturnCached(Type: string, Path: string): boolean?
	assert(Type and Path, `[ParcelAPI]: Expected Type and Path, got {Type} {Path}`)
	assert(self.CacheDurations[Type], `[ParcelAPI]: CacheDuration for Type {Type} does not exist!`)
	assert(self.Cache and self.Cache[Type], `[ParcelAPI]: Cache does not exist, or {Type} is an invalid type!`)

	local Object = self.Cache[Type][Path]
	local CacheDuration = self.CacheDurations[Type]

	local Expired = Object and (Object.GeneratedAt + CacheDuration) < os.time()
	local SuggestCachedResponse = (Object ~= nil) and ((CacheDuration < 0) or not Expired)

	self:_Debug(`Suggesting to respond with a {SuggestCachedResponse and "cached" or "fresh"} response for {Type}/{Path}`)

	return SuggestCachedResponse
end

function ParcelAPI:_SetCache(Type: string, Path: string, Result: any?): boolean
	if self.Cache[Type][Path] then
		local ResultOK, Response = pcall(self._ShouldReturnCached, self, Type, Path)

		if ResultOK and not Response then
			return false
		end
	end

	self:_Debug(`Updating [{Type}][{Path}] in cache`)

	self.Cache[Type][Path] = {
		Data = Result,
		GeneratedAt = os.time()
	}
end

function ParcelAPI:_FormatPackablesObject(Packables: {[any]: any}): Packables?
	if not Packables then
		return
	end

	return {
		Delivery = Packables.delivery,
		DisplayRobux = Packables.display_robux,
		IsUSDOnsale = Packables.onsale_usd,
		USDPrice = tonumber(Packables.price_in_usd),
		Stripe = Packables.stripe,
	}
end

function ParcelAPI:_FormatProductObject(Product: {[any]: any}): Product?
	if not Product then
		return
	end

	local ProductStock = type(Product.stock) == "boolean" and Product.stock or tonumber(Product.stock)
	local ProductPackables = self:_FormatPackablesObject(Product.packables)

	return {
		-- generic details
		Name = Product.name,
		Description = Product.description,
		DecalId = tonumber(Product.decalID),

		-- tags
		Category = Product.category,
		Tags = Product.tags,

		-- pricing
		Stock = ProductStock,
		ProductId = Product.productID,
		DeveloperProductId = tonumber(Product.devproduct_id),

		-- packables
		Packables = ProductPackables,		
	}
end

-- External
export type HubInfo = { TotalSales: number, MusicId: number }?
function ParcelAPI:FetchHubInfo(): HubInfo
	-- hub/getinfo
	if self:_ShouldReturnCached("Hub", "getinfo") then
		self:_Debug("returning cached responses")
		return self.Cache.Hub["getinfo"].Data
	end

	local RequestOk, Data = self:_Request("hub/getinfo")

	if not RequestOk then
		return
	end

	-- format data
	local FormattedData = {
		TotalSales = tonumber(Data.totalSales or "0"),
		MusicId = tonumber(Data.musicId or "0")
	}

	self:_SetCache("Hub", "getinfo", FormattedData)
	return FormattedData
end

export type HubDescription = { LongDescription: string, ShortDescription: string }?
function ParcelAPI:FetchHubDescription(): HubDescription
	-- hub/description
	if self:_ShouldReturnCached("Hub", "description") then
		return self.Cache.Hub["description"].Data
	end

	local RequestOk, Data = self:_Request("hub/description")

	if not RequestOk then
		return
	end

	-- format data
	local FormattedData = {
		LongDescription = Data.details.long_description,
		ShortDescription = Data.details.short_description
	}

	self:_SetCache("Hub", "description", FormattedData)
	return FormattedData
end

export type HubTerms = { Terms: string }?
function ParcelAPI:FetchHubTerms(): HubTerms
	-- hub/terms
	if self:_ShouldReturnCached("Hub", "terms") then
		return self.Cache.Hub["terms"].Data
	end

	local RequestOk, Data = self:_Request("hub/terms")

	if not RequestOk then
		return
	end

	-- format data
	local FormattedData = {
		Terms = Data.details.terms
	}

	self:_SetCache("Hub", "terms", FormattedData)
	return FormattedData
end

function ParcelAPI:FetchBestseller(): { HubId: string, Product: Product?}?
	-- hub/getproducts?option=bestseller
	return self:FetchProducts(true)
end

export type HubProducts = { HubId: string, Products: {Product}?, Product: Product? }?
function ParcelAPI:FetchProducts(GetBestseller: boolean?): HubProducts
	-- hub/getproducts (GetBestseller and "?option=bestseller")
	local CachePath = `products{GetBestseller and ".bestseller" or ""}`
	if self:_ShouldReturnCached("Products", CachePath) then
		return self.Cache.Products[CachePath].Data
	end

	local RequestOk, Data = self:_Request(`hub/getproducts{GetBestseller and "?option=bestseller" or ""}`)

	if not RequestOk then
		return
	end

	-- format data
	local FormattedData = {}

	if GetBestseller then
		FormattedData.HubId = Data.details.hubId
		FormattedData.Product = self:_FormatProductObject(Data.details.product)
	else
		FormattedData.HubId = Data.details.hubId
		FormattedData.Products = {}

		for _, ProductObject in pairs(Data.details.products) do
			local FormattedProduct = self:_FormatProductObject(ProductObject)

			table.insert(FormattedData.Products, FormattedProduct)
		end
	end

	self:_SetCache("Products", CachePath, FormattedData)
	return FormattedData
end

function ParcelAPI:FetchPlayerOwnedProducts(UserId: RobloxId)
	-- hub/user/getproducts/
	assert(
		UserId and typeof(UserId) == "number",
		`[ParcelAPI]: Invalid UserId provided! Expected <number>, got <{typeof(UserId)}>`
	)

	local CachePath = `ownedproducts.{tostring(UserId)}`
	if self:_ShouldReturnCached("Players", CachePath) then
		return self.Cache.Players[CachePath].Data
	end

	local RequestOk, Data = self:_Request(`hub/user/getproducts/{UserId}`)

	if not RequestOk then
		return
	end

	-- format data
	local FormattedData = {}

	for _, ProductObject in pairs(Data.details.ownedProducts) do
		local Product = self:_FormatProductObject(ProductObject)
		table.insert(FormattedData, Product)
	end

	self:_SetCache("Players", CachePath, FormattedData)
	return FormattedData
end

export type PlayerProfile = { DiscordId: string, IsVerified: boolean, RobloxId: number, DiscordTag: string }?
function ParcelAPI:FetchPlayerProfile(UserId: RobloxId | DiscordId, ProvidedUserType: UserType): PlayerProfile
	-- "user/check/".. UserId .. "?option=".. UserType,
	assert(
		UserId and typeof(UserId) == "number",
		`[ParcelAPI]: Invalid UserId provided! Expected <number>, got <{typeof(UserId)}>`
	)

	assert(
		ProvidedUserType and typeof(ProvidedUserType) == "string",
		`[ParcelAPI]: Invalid UserType provided! Expected <string>, got <{typeof(ProvidedUserType)}>`
	)

	local CachePath = `profile.{tostring(UserId)}`
	if self:_ShouldReturnCached("Players", CachePath) then
		return self.Cache.Players[CachePath].Data
	end

	local RequestOk, Data = self:_Request(`user/check/{UserId}?option={ProvidedUserType}`)

	if not RequestOk then
		return
	end

	-- format data
	local FormattedData = {
		DiscordId = Data.details.discordID,
		IsVerified = Data.details.verified,
		RobloxId = tonumber(Data.details.robloxID or "0"),
		DiscordTag = Data.details.discordTag
	}

	self:_SetCache("Players", CachePath, FormattedData)
	return FormattedData
end

function ParcelAPI:Whitelist(UserId: RobloxId, ProductId: ProductId): (boolean, string | {message: string, status: number})
	-- hub/order/complete
	assert(
		UserId and ProductId,
		`[ParcelAPI]: Invalid parameters passed while attempting to Whitelist {UserId}!`
	)
	return self:_Request(`hub/order/complete`, "POST", {
		robloxID = tonumber(UserId),
		productID = tostring(ProductId)
	}, true)
end

-- External Initialiser
return function(AuthToken: string?, ForceDebugging: boolean?)
	local _RetrievedSecret, EmbeddedSecret = pcall(HttpService.GetSecret, HttpService, "ParcelToken")

	assert(
		AuthToken or EmbeddedSecret,
		"[ParcelAPI]: Cannot initialise a new ParcelInstance, no AuthToken provided, and none found as a secret!"
	)

	assert(
		RunService:IsServer(),
		"[ParcelAPI]: Cannot initialise a new ParcelInstance, current environment is not the server!"
	)

	local ParcelInstance = setmetatable({
		AuthToken = AuthToken or EmbeddedSecret,
		Cache = {
			Hub = {},
			Products = {},
			Players = {}
		},

		CacheDurations = {
			Hub = -1, -- Always cache
			Products = 60, -- Refresh cache if data is older than 60 seconds
			Players = 5
		},

		Debugging = 
			if (type(ForceDebugging) == "boolean") then ForceDebugging
			else RunService:IsStudio()
	}, ParcelAPI)

	-- Verify the token is genuine
	ParcelInstance:_IntegrityCheck()
	return table.freeze(ParcelInstance)
end :: (AuthString: string?, ForceDebugging: boolean?) -> {
	---@diagnostic disable: undefined-type
	FetchHubInfo: (self: ParcelAPI) -> HubInfo,
	FetchHubDescription: (self: ParcelAPI) -> HubDescription,
	FetchHubTerms: (self: ParcelAPI) -> HubTerms,
	FetchBestseller: (self: ParcelAPI) -> Product?,
	FetchProducts: (self: ParcelAPI, GetBestseller: boolean?) -> HubProducts,
	FetchPlayerOwnedProducts: (self: ParcelAPI, UserId: RobloxId) -> {Product?},
	FetchPlayerProfile: (self: ParcelAPI, UserId: RobloxId | DiscordId, ProvidedUserType: UserType) -> PlayerProfile,
	Whitelist: (self: ParcelAPI, UserId: RobloxId, ProductId: ProductId) -> (boolean, string | {message: string, status: number}),
}
