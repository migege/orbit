import { Body, ConflictException, Controller, Get, Patch, Post, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { AuthUser, CurrentUser } from '../common/current-user.decorator';
import { generateToken, hashPassword } from '../common/crypto.util';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { AdminAuthGuard } from './admin-auth.guard';
import { CreateUserDto, UpdatePreferencesDto } from './dto';

@Controller('users')
export class UsersController {
  constructor(private readonly prisma: PrismaService) {}

  @UseGuards(JwtAuthGuard)
  @Get('me')
  me(@CurrentUser() user: AuthUser) {
    return this.prisma.user.findUnique({
      where: { id: user.userId },
      select: { id: true, email: true, name: true, createdAt: true, preferences: true },
    });
  }

  /**
   * Patch the current user's own preferences. The body is a partial set of keys
   * (theme / new-agent defaults); each present key is shallow-merged into the
   * stored JSON, so omitted keys keep their value. Returns the same shape as `me`.
   */
  @UseGuards(JwtAuthGuard)
  @Patch('me/preferences')
  async updatePreferences(@CurrentUser() user: AuthUser, @Body() dto: UpdatePreferencesDto) {
    const current = await this.prisma.user.findUnique({
      where: { id: user.userId },
      select: { preferences: true },
    });
    const merged = { ...((current?.preferences ?? {}) as Record<string, unknown>) };
    if (dto.theme !== undefined) merged.theme = dto.theme;
    if (dto.defaultModel !== undefined) merged.defaultModel = dto.defaultModel;
    if (dto.defaultPermissionMode !== undefined) merged.defaultPermissionMode = dto.defaultPermissionMode;
    return this.prisma.user.update({
      where: { id: user.userId },
      data: { preferences: merged as Prisma.InputJsonValue },
      select: { id: true, email: true, name: true, createdAt: true, preferences: true },
    });
  }

  /**
   * Provision a user. Self-registration was removed, so accounts are created
   * here behind ADMIN_TOKEN — the API equivalent of the add-user script.
   * Password hashing matches crypto.util so the account can log in normally.
   */
  @UseGuards(AdminAuthGuard)
  @Post()
  async create(@Body() dto: CreateUserDto) {
    const email = dto.email.trim();
    const name = dto.name?.trim() || email.split('@')[0];

    const existing = await this.prisma.user.findUnique({ where: { email } });
    if (existing && !dto.force) {
      throw new ConflictException(`user ${email} already exists (set force to reset their password)`);
    }

    let password = dto.password;
    let generated = false;
    if (!password) {
      password = generateToken(12);
      generated = true;
    }
    const passwordHash = hashPassword(password);

    const user = existing
      ? await this.prisma.user.update({ where: { email }, data: { passwordHash } })
      : await this.prisma.user.create({ data: { email, name, passwordHash } });

    return {
      id: user.id,
      email: user.email,
      name: user.name,
      reset: Boolean(existing),
      ...(generated ? { generatedPassword: password } : {}),
    };
  }
}
