# Managed by Ansible (teamcraft-deploy, role glitchtip). Runs inside GlitchTip's web container
# (`manage.py shell -c`), started by the timer glitchtip-sso-role-sync of tc-glitchtip.
#
# GlitchTip adds people who sign in through an organization's SSO app as members, but has no role
# mapping. This sets each SSO user's organization role from a claim of the identity provider, as the
# claims were at the user's last SSO sign-in (allauth keeps them in SocialAccount.extra_data). Only
# accounts of that organization's SSO app are touched; local accounts (the superuser) never are. An
# organization always keeps an owner. Settings come from the environment (docs/components/glitchtip.md):
#   GLITCHTIP_SSO_ROLE_CLAIM          claim name, e.g. glitchtip_roles
#   GLITCHTIP_SSO_ROLE_MAP_B64        base64 of JSON: claim value -> owner|manager|admin|member
#   GLITCHTIP_SSO_REMOVE_WITHOUT_ROLE true: remove members whose claim maps to no role
import base64
import json
import logging
import os

from allauth.socialaccount.models import SocialAccount
from django.db import transaction

from apps.organizations_ext.constants import OrganizationUserRole
from apps.organizations_ext.models import OrganizationOwner, OrganizationSocialApp, OrganizationUser

ROLES = {
    "owner": OrganizationUserRole.OWNER,
    "manager": OrganizationUserRole.MANAGER,
    "admin": OrganizationUserRole.ADMIN,
    "member": OrganizationUserRole.MEMBER,
}

log = logging.getLogger("sso-role-sync")


def main():
    logging.basicConfig(level=logging.INFO, format="%(message)s", force=True)
    claim = os.environ.get("GLITCHTIP_SSO_ROLE_CLAIM", "")
    if not claim:
        return
    mapping = json.loads(base64.b64decode(os.environ["GLITCHTIP_SSO_ROLE_MAP_B64"]))
    role_map = {str(value): ROLES[role.lower()] for value, role in mapping.items()}
    remove_without_role = os.environ.get("GLITCHTIP_SSO_REMOVE_WITHOUT_ROLE", "true").lower() == "true"
    changes = 0
    links = OrganizationSocialApp.objects.select_related("organization", "social_app")
    for link in links:
        with transaction.atomic():
            changes += sync_organization(link.organization, link.social_app, claim, role_map, remove_without_role)
    log.info("SSO role sync: %d change(s)", changes)


def sync_organization(organization, social_app, claim, role_map, remove_without_role):
    # Like GlitchTip's own lookup (apps.users.utils): OIDC accounts carry the app's provider_id.
    provider = social_app.provider_id or social_app.provider
    members = {m.user_id: m for m in OrganizationUser.objects.filter(organization=organization, user__isnull=False)}
    changes = 0
    for account in SocialAccount.objects.filter(provider=provider).select_related("user").order_by("user_id"):
        role = highest_role(claim_values(account.extra_data, claim), role_map)
        member = members.get(account.user_id)
        if member is None:
            if role is not None:
                # GlitchTip's own way in (the first user of an empty organization becomes its owner).
                organization.add_user(account.user, role=role)
                log.info("org %s: user %s added as %s", organization.id, account.user_id, role.label)
                changes += 1
        elif role is None:
            if remove_without_role and leave_owner_role(organization, member):
                member.delete()
                log.info("org %s: user %s removed (no role in claim %s)", organization.id, account.user_id, claim)
                changes += 1
        elif member.role != role:
            if role >= OrganizationUserRole.OWNER or leave_owner_role(organization, member):
                old = OrganizationUserRole(member.role).label
                member.role = role
                member.save(update_fields=["role"])
                log.info("org %s: user %s %s -> %s", organization.id, account.user_id, old, role.label)
                changes += 1
    return changes


def claim_values(extra_data, claim):
    """The claim's values: allauth's openid_connect stores {"userinfo": ..., "id_token": ...}; older
    accounts and other providers keep the claims at the top level."""
    if not isinstance(extra_data, dict):
        return []
    for source in (extra_data.get("userinfo"), extra_data.get("id_token"), extra_data):
        if isinstance(source, dict) and claim in source:
            value = source[claim]
            if isinstance(value, (list, tuple)):
                return [str(v) for v in value]
            if isinstance(value, str):
                return value.replace(",", " ").split()
            return [str(value)]
    return []


def highest_role(values, role_map):
    roles = [role_map[v] for v in values if v in role_map]
    return max(roles) if roles else None


def leave_owner_role(organization, member):
    """Whether member may stop being an owner: always if it isn't one; otherwise only while another
    owner remains, who then also becomes the primary owner if member was it."""
    if member.role < OrganizationUserRole.OWNER:
        return True
    others = OrganizationUser.objects.filter(
        organization=organization, role__gte=OrganizationUserRole.OWNER, user__isnull=False
    ).exclude(id=member.id)
    other = others.order_by("id").first()
    if other is None:
        log.warning("org %s: user %s stays owner (the organization's last owner)", organization.id, member.user_id)
        return False
    primary = OrganizationOwner.objects.filter(organization=organization).first()
    if primary is not None and primary.organization_user_id == member.id:
        primary.organization_user = other
        primary.save(update_fields=["organization_user"])
        log.info("org %s: primary owner is now user %s", organization.id, other.user_id)
    return True


main()
