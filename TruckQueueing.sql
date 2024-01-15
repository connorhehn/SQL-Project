-- Connor Hehn
drop table TruckQueue
go
create table TruckQueue (
	truckID uniqueidentifier primary key nonclustered,
	queueID int identity(1,1),
	truckSize char(1) -- L or S
	);
go

drop table Bays
go
create table Bays (
	bayNum int primary key,
	truckid uniqueidentifier,
	baySize char(1),
	truckSize char(1)
	);
go

-- Bay 1 and 2 are large; bay 3 and 4 are small
create or alter procedure initializeBays
as
begin
	insert into Bays values (1,NULL,'L',null)
	insert into Bays values (2,NULL,'L',null)
	insert into Bays values (3,NULL,'S',null)
	insert into Bays values (4,NULL,'S',null)
end;
go

exec initializeBays; --MUST RUN THIS TO INITIALIZE BAYS
go

-- Add truck to queue
create or alter procedure queueTruck (@size char(1))
as
begin
	if @size in ('L','S')
	begin
		insert into TruckQueue (truckID,truckSize)
		values (newid(),@size)
	end
	else
	begin
		print 'Not valid truck size. Enter L or S.'
		return;
	end;
end;
go

-- Get next small truck function
create or alter function getNextSmall ()
returns uniqueidentifier
begin
	declare @truck uniqueidentifier;
	with smallTrucks as
	(
		select *
		from TruckQueue
		where truckSize = 'S'
	)
	select top 1 @truck = truckID
	from smallTrucks
	order by queueID;
	return @truck
end;
go

-- Get next large truck function
create or alter function getNextLarge ()
returns uniqueidentifier
begin
	declare @truck uniqueidentifier;
	with largeTrucks as
	(
		select *
		from TruckQueue
		where truckSize = 'L'
	)
	select top 1 @truck = truckID
	from largeTrucks
	order by queueID;
	return @truck
end;
go

-- Delete truck from queue helper procedure
create or alter procedure deleteTruckFromQueue(@truck uniqueidentifier)
as
begin
	delete from TruckQueue
	where truckID = @truck
end;
go


-- Add truck to bay
create or alter procedure addTruckToBay (@bayNum int)
as
begin
	-- Check valid bay
	if not exists (select bayNum from Bays where bayNum = @bayNum)
	begin
		print 'Not a valid bay number'
		return;
	end;

	-- Check if bay is occupied
	if (select truckid from Bays where bayNum = @bayNum) is not null
	begin
		print 'Bay ' +convert(varchar,@bayNum) + ' is currently occupied. Unload bay first.'
		return;
	end;

	declare @size char(1)
	declare @truck uniqueidentifier
	set @size = (select baySize from Bays where bayNum = @bayNum);

	-- Small bay (can only take in small trucks)
	if @size = 'S'
	begin
		set @truck = (select dbo.getNextSmall());

		if @truck is null
		begin
			print 'No small trucks are waiting'
			return;
		end;

		update Bays
		set truckID = @truck, truckSize = @size
		where bayNum = @bayNum;
		exec deleteTruckFromQueue @truck;
		return;
	end;

	-- Large bay (check if large trucks in queue, if not take a small truck)
	if @size = 'L'
	begin
		set @truck = (select dbo.getNextLarge());

		if @truck is null
		begin
			set @truck = (select dbo.getNextSmall());
			set @size = 'S';
			if @truck is null
			begin
				print 'No trucks currently in queue'
				return
			end
		end

		update Bays
		set truckID = @truck, truckSize = @size
		where bayNum = @bayNum;
		exec deleteTruckFromQueue @truck;
		return;
	end;
end;
go


-- Unload specific bay
create or alter procedure unloadBay(@bayNum int)
as
begin

	if not exists (select bayNum from Bays where bayNum = @bayNum)
	begin
		print 'Not a valid bay number'
		return;
	end;

	-- Check if bay is occupied
	if (select truckid from Bays where bayNum = @bayNum) is null
	begin
		print 'Bay ' +convert(varchar,@bayNum) + ' is currently empty.'
		return;
	end;

	update Bays
	set truckID = null, truckSize = null
	where bayNum = @bayNum
	return;
end;
go

-- Unload all bays
create or alter procedure unloadAllBays
as
begin
	update Bays
	set truckID = null, truckSize = null
	return;
end;
go

-- Service Bay (unload current bay, remove truck from bay, and add new truck)
create or alter procedure serviceBay (@bayNum int)
as
begin
	-- Ensure input is a valid bay
	if not exists (select bayNum from Bays where bayNum = @bayNum)
	begin
		print 'Not a valid bay number'
		return;
	end;

	exec unloadBay @bayNum;
	exec addTruckToBay @bayNum;
	return;
end;
go

-- Service all bays
create or alter procedure serviceAllBays
as
begin
	exec serviceBay 1;
	exec serviceBay 2;
	exec serviceBay 3;
	exec serviceBay 4;
end;
go


-- TESTS
-- Test Case 1 (All small trucks)
delete from TruckQueue
exec unloadAllBays

exec queueTruck 'S'
exec queueTruck 'S'
exec queueTruck 'S'
exec queueTruck 'S'
exec queueTruck 'S'
exec queueTruck 'S'

select * from TruckQueue order by queueID
select * from Bays

exec serviceBay 1 -- serviceBay will remove any existing truck from bay, and add the next truck
exec serviceBay 2
exec serviceBay 3
exec serviceBay 4

select * from TruckQueue order by queueID
select * from Bays
go

-- Test Case 2 (All large trucks)
delete from TruckQueue
exec unloadAllBays

exec queueTruck 'L'
exec queueTruck 'L'
exec queueTruck 'L'
exec queueTruck 'L'
exec queueTruck 'L'
exec queueTruck 'L'

select * from TruckQueue order by queueID
select * from Bays

exec serviceAllBays -- This does this in order from bay 1 to bay 4

select * from TruckQueue order by queueID
select * from Bays
go

-- Test Case 3 (Small trucks, followed by large)
delete from TruckQueue
exec unloadAllBays
exec queueTruck 'S'
exec queueTruck 'S'
exec queueTruck 'S'
exec queueTruck 'S'
exec queueTruck 'L'
exec queueTruck 'L'

select * from TruckQueue order by queueID
select * from Bays

exec serviceAllBays

select * from TruckQueue order by queueID
select * from Bays
go

-- Test case 4 (invalid inputs)
delete from TruckQueue
exec unloadAllBays
exec queueTruck 'big'
exec serviceBay 6
