import { Body, ConflictException, Controller, Get, Post, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { AuthUser, CurrentUser } from '../common/current-user.decorator';
import { generateToken, hashPassword } from '../common/crypto.util';
import { PrismaService } from '../prisma/prisma.service';
import { AdminAuthGuard } from './admin-auth.guard';
import { CreateUserDto } from './dto';

@Controller('users')
export class UsersController {
  constructor(private readonly prisma: PrismaService) {}

  @UseGuards(JwtAuthGuard)
  @Get('me')
  me(@CurrentUser() user: AuthUser) {
    return this.prisma.user.findUnique({
      where: { id: user.userId },
      select: { id: true, email: true, name: true, createdAt: true },
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
