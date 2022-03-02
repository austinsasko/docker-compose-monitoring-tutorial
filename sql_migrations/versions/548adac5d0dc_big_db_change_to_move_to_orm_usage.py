"""Big DB change to move to ORM usage

Revision ID: 548adac5d0dc
Revises: 93d52238615e
Create Date: 2022-01-08 17:47:33.813354-05:00

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '548adac5d0dc'
down_revision = '93d52238615e'
branch_labels = None
depends_on = None


def upgrade():
      #create discord_users
    op.create_table(
        'discord_users',
        sa.Column('discord_id', sa.BigInteger(), primary_key=True),
        sa.Column('discord_display_name', sa.String(255)),
        sa.Column('discord_created', sa.TIMESTAMP, nullable=True),
        sa.Column('discord_joined', sa.TIMESTAMP, nullable=True)
    )

    #rename staff_tracker.id and add FK
    op.alter_column("vc_tracker", "id", new_column_name="discord_id", nullable=False, primary_key=True, existing_type=sa.BigInteger())
    op.create_foreign_key('fk_vc_tracker_discord_users', 'vc_tracker', 'discord_users', ['discord_id'], ['discord_id'])

def downgrade():
    op.alter_column("vc_tracker", "discord_id", new_column_name="id", nullable=False, primary_key=True, existing_type=sa.BigInteger())
    op.drop_constraint(constraint_name="fk_vc_tracker_discord_users", table_name="vc_tracker", type_="foreignkey")
    op.drop_table('discord_users')
