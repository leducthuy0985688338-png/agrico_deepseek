import 'dart:convert';
import '../../../lib/core/permissions/company_roles.dart';
void main() => print(jsonEncode({for(final role in CompanyRole.values) role.name: CompanyRolePolicy.permissions(role).toList()}));
