"""Add staff tracked DB

Revision ID: 93d52238615e
Revises: c9923e0f957b
Create Date: 2021-12-30 22:17:31.946529-05:00

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '93d52238615e'
down_revision = None
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        'vc_tracker',
        sa.Column('id', sa.BigInteger(), primary_key=True),
        sa.Column('channel_id', sa.BigInteger()),
        sa.Column('minutes_logged', sa.Integer())
    )


def downgrade():
    op.drop_table('vc_tracker')
