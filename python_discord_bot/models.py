from sqlalchemy import Column, Integer, String, BigInteger, TIMESTAMP, Enum, ForeignKey, text
from sqlalchemy import update as sqlalchemy_update
from sqlalchemy.future import select
from sqlalchemy.orm import relationship, backref
from sqlalchemy.sql.expression import desc, func
from sqlalchemy.sql.functions import current_timestamp
from copy import deepcopy
from sqlalchemy.dialects.mysql.dml import Insert 
from sqlalchemy import and_
from sqlalchemy.orm import declarative_base
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.ext.asyncio import create_async_engine
from sqlalchemy.orm import sessionmaker
import os

Base = declarative_base()

class ModelAdmin:
    @classmethod
    async def create_engine(self):
        if not hasattr(self, 'engine'):
            db_host="mariadb"
            db_port=3306
            if os.getenv("STAGING"):
                db_host="mariadb_staging"
                db_port=os.getenv("DB_PORT")
            engine = create_async_engine(f"mysql+asyncmy://{os.getenv('DB_USER')}:{os.getenv('DB_PASS')}@{db_host}:{db_port}/{os.getenv('DB_NAME')}",
                echo=True, 
                future=True,
                pool_recycle=3600,
            )
            self.engine = engine
        return self.engine
        
    async def conn(self, engine, add=False, execu=False, param=None):
        session = sessionmaker(
            engine, expire_on_commit=False, class_=AsyncSession
        )
        async with session() as dbsess:
            async with dbsess.begin():
                if add:
                    output = dbsess.add(param)
                if execu:
                    output = await dbsess.execute(param)
        return output

    async def check_disc_fk(self, **kwargs):
        engine = await self.create_engine()
        if not kwargs:
            discord_arg = {"discord_id": self.discord_id}
        else:
            discord_arg = {"discord_id": kwargs.get("discord_id")}
        select_query = select(DiscordUser().__class__).filter_by(**discord_arg)
        results = await self.conn(engine, False, True, select_query)
        result = results.one_or_none()
        if not result:
            await DiscordUser().create(**discord_arg)

    async def create(self, **kwargs):
        engine = await self.create_engine()
        if self.__class__ != DiscordUser:
            await self.check_disc_fk(**kwargs)
        if not kwargs:
            await self.conn(engine, True, False, deepcopy(self))
        else:
            await self.conn(engine, True, False, self.__class__(**kwargs))

    async def insert_or_update(self, value_dict, /, **kwargs):
        engine = await self.create_engine()
        if self.__class__ != DiscordUser:
            await self.check_disc_fk(**kwargs)
        stmt = Insert(self.__class__).values(**kwargs).on_duplicate_key_update(**value_dict,)
        await self.conn(engine, False, True, stmt)

    async def update(self, filterargs=None, **kwargs):
        engine = await self.create_engine()
        if not filterargs:
            await self.conn(engine, True, False, deepcopy(self))
        else:
            query = (
                sqlalchemy_update(self.__class__)
                .filter_by(**filterargs)
                .values(**kwargs)
                .execution_options(synchronize_session="fetch")
            )
            await self.conn(engine, False, True, query)

    async def get(self, all=False, count=False, order_by=None, **kwargs):
        engine = await self.create_engine()
        query = select(self.__class__).filter_by(**kwargs).order_by(desc(order_by))
        if count:
            query = (query.with_only_columns([func.count()]).order_by(desc(order_by)))
        results = await self.conn(engine, False, True, query)
        if all:
            result = results.all()
        else:
            result = results.one_or_none()
        return result

    async def delete(self, **kwargs):
        engine = await self.create_engine()
        query = self.__class__.__table__.delete().filter_by(**kwargs)
        await self.conn(engine, False, True, query)


class VCTracker(Base, ModelAdmin):
    __tablename__ = "staff_tracker"
    id = Column(BigInteger, autoincrement=True, primary_key=True)
    discord_id = Column(BigInteger, ForeignKey('discord_users.discord_id'))
    channel_id = Column(BigInteger)
    minutes_logged = Column(Integer)

    discord = relationship("DiscordUser", uselist=False, backref="staff_tracker", lazy='selectin')

    __mapper_args__ = {"eager_defaults": True}

    def __repr__(self):
        return (
                f"<{self.__class__.__name__}("
                f"discord_id={self.discord_id}, "
                f"channel_id={self.channel_id}, "
                f"minutes_logged={self.minutes_logged}, "
                f"disc_rel={self.discord}, "
                f")>"
        )

    @classmethod
    async def test():
        pass

class DiscordUser(Base, ModelAdmin):
    __tablename__ = "discord_users"
    discord_id = Column(BigInteger, primary_key=True)
    discord_display_name = Column(String(255))
    discord_created = Column(TIMESTAMP, nullable=True)
    discord_joined = Column(TIMESTAMP, nullable=True)
    __mapper_args__ = {"eager_defaults": True}

    def __repr__(self):
        return (
                f"<{self.__class__.__name__}("
                f"discord_id={self.discord_id}, "
                f"discord_display_name={self.discord_display_name}, "
                f"discord_created={self.discord_created}, "
                f"discord_joined={self.discord_joined}, "
                f")>"
        )

